import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:auto_task_scheduler/models/task_model.dart';
import 'package:auto_task_scheduler/providers/planner_provider.dart';
import 'package:auto_task_scheduler/screens/plan_day_screen.dart';
import 'package:auto_task_scheduler/services/database_service.dart';
import 'package:auto_task_scheduler/services/gemini_service.dart';

GeminiHttpResponse estimate(List tasks) => GeminiHttpResponse(
  200,
  jsonEncode({
    'candidates': [
      {
        'finishReason': 'STOP',
        'content': {
          'parts': [
            {
              'text': jsonEncode({
                'tasks': tasks
                    .map(
                      (task) => {
                        'input_index': task['input_index'],
                        'duration_minutes': task['duration_minutes'] == 0
                            ? 5
                            : task['duration_minutes'],
                      },
                    )
                    .toList(),
              }),
            },
          ],
        },
      },
    ],
  }),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('basic estimates are identified to the user', () async {
    final service = GeminiService(
      transport: (_, __, body) async {
        final input = jsonDecode(
          jsonDecode(body)['contents'][0]['parts'][0]['text'],
        );
        final response = estimate(input['tasks'] as List);
        return GeminiHttpResponse(
          200,
          jsonEncode({...jsonDecode(response.body), 'source': 'basic'}),
        );
      },
    );
    final result = await service.generate(
      tasks: [TaskModel(title: 'Check email', durationMinutes: 0)],
      date: DateTime(2026, 11, 24),
      startTime: '9:00 AM',
      breakCount: 0,
      breakMinutes: 0,
    );
    expect(result.single.durationMinutes, 5);
    expect(service.notice, contains('basic time estimates'));
  });
  test(
    '200 auto tasks are estimated in bounded batches without omissions',
    () async {
      final sizes = <int>[], progress = <int>[];
      final service = GeminiService(
        transport: (_, __, body) async {
          final input = jsonDecode(
            jsonDecode(body)['contents'][0]['parts'][0]['text'],
          );
          final tasks = input['tasks'] as List;
          sizes.add(tasks.length);
          expect(
            input['available_focus_minutes'],
            greaterThanOrEqualTo(tasks.length * 5),
          );
          return estimate(tasks);
        },
      );
      final result = await service.generate(
        tasks: List.generate(
          200,
          (i) =>
              TaskModel(id: i + 1, title: 'Task ${i + 1}', durationMinutes: 0),
        ),
        date: DateTime(2026, 11, 24),
        startTime: '12:00 AM',
        breakCount: 0,
        breakMinutes: 0,
        onProgress: (completed, _) => progress.add(completed),
      );
      expect(sizes, List.filled(8, 25));
      expect(result.map((task) => task.id), List.generate(200, (i) => i + 1));
      expect(result.every((task) => task.durationMinutes == 5), isTrue);
      expect(progress.last, 200);
    },
  );

  test(
    'insufficient day length is rejected before sending an API request',
    () async {
      var called = false;
      final service = GeminiService(
        transport: (_, __, ___) async {
          called = true;
          return estimate([]);
        },
      );
      await expectLater(
        service.generate(
          tasks: List.generate(
            200,
            (i) => TaskModel(title: 'Task $i', durationMinutes: 0),
          ),
          date: DateTime(2026, 11, 24),
          startTime: '9:00 AM',
          breakCount: 1,
          breakMinutes: 5,
        ),
        throwsA(
          isA<GeminiException>().having(
            (e) => e.message,
            'message',
            contains('Start earlier'),
          ),
        ),
      );
      expect(called, isFalse);
    },
  );

  test('a later batch failure keeps every original draft task', () async {
    final db = await DatabaseService.inMemory();
    var calls = 0;
    final planner = PlannerProvider(
      database: db,
      gemini: GeminiService(
        transport: (_, __, body) async {
          calls++;
          if (calls == 2) return const GeminiHttpResponse(503, '{}');
          final input = jsonDecode(
            jsonDecode(body)['contents'][0]['parts'][0]['text'],
          );
          return estimate(input['tasks'] as List);
        },
      ),
    );
    await planner.ready;
    planner.preparePlanDraft();
    expect(planner.addDraftTasks(List.generate(60, (i) => 'Task $i')), isTrue);
    await expectLater(
      planner.generateAndSaveDraft(),
      throwsA(isA<GeminiException>()),
    );
    expect(planner.draftTasks, hasLength(60));
    expect(
      planner.draftTasks.every((task) => task.durationMinutes == 0),
      isTrue,
    );
    expect(planner.currentPlan, isNull);
    planner.dispose();
    await db.close();
  });

  test(
    '200 fixed tasks save without Gemini and bulk additions are atomic',
    () async {
      final db = await DatabaseService.inMemory();
      final planner = PlannerProvider(
        database: db,
        gemini: GeminiService(
          transport: (_, __, ___) async =>
              throw StateError('Unnecessary API call'),
        ),
      );
      await planner.ready;
      planner.preparePlanDraft();
      expect(
        planner.addDraftTasks(
          List.generate(200, (i) => 'Task $i'),
          duration: 1,
        ),
        isTrue,
      );
      expect(planner.addDraftTask('Extra'), isFalse);
      expect(planner.draftTasks, hasLength(200));
      await planner.generateAndSaveDraft();
      expect(planner.currentPlan!.tasks, hasLength(200));
      expect(
        (await db.getPlanForDate(planner.currentPlan!.planDate))!.tasks,
        hasLength(200),
      );
      planner.dispose();
      await db.close();
    },
  );

  test(
    'delete removes the task and schedule, keeps other progress, and supports the final task',
    () async {
      final db = await DatabaseService.inMemory();
      final planner = PlannerProvider(database: db);
      await planner.ready;
      planner.preparePlanDraft();
      planner.addDraftTask('Review', duration: 25);
      planner.addDraftTask('Unwinding', duration: 15);
      await planner.generateAndSaveDraft(useGemini: false);
      final date = planner.currentPlan!.planDate;
      await planner.setTaskCompletion(
        planner.currentPlan!.tasks.first.id!,
        true,
      );
      await planner.deleteTask(planner.currentPlan!.tasks.last.id!);
      expect(planner.currentPlan!.tasks.single.title, 'Review');
      expect(planner.currentPlan!.tasks.single.isCompleted, isTrue);
      expect(
        planner.currentPlan!.scheduleSlots.any(
          (slot) => slot.title == 'Unwinding',
        ),
        isFalse,
      );
      await planner.deleteTask(planner.currentPlan!.tasks.single.id!);
      expect(planner.currentPlan, isNull);
      expect(await db.getPlanForDate(date), isNull);
      planner.preparePlanDraft();
      planner.addDraftTask('New task', duration: 5);
      await planner.generateAndSaveDraft(useGemini: false);
      expect(planner.currentPlan!.tasks.single.title, 'New task');
      planner.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await db.close();
    },
  );

  testWidgets('a 200-task draft builds only visible task controls', (
    tester,
  ) async {
    late DatabaseService db;
    late PlannerProvider planner;
    await tester.runAsync(() async {
      db = await DatabaseService.inMemory();
      planner = PlannerProvider(database: db);
      await planner.ready;
      planner.preparePlanDraft();
      planner.addDraftTasks(List.generate(200, (i) => 'Task $i'));
    });
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: planner,
        child: const MaterialApp(home: PlanDayScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(DropdownButton<int>).evaluate().length, lessThan(20));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    planner.dispose();
    await tester.runAsync(db.close);
  });
}
