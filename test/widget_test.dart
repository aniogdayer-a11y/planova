import 'dart:convert';
import 'package:auto_task_scheduler/services/gemini_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:auto_task_scheduler/main.dart';
import 'package:auto_task_scheduler/providers/planner_provider.dart';
import 'package:auto_task_scheduler/services/database_service.dart';
import 'package:auto_task_scheduler/widgets/calendar_widget.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('phone flow creates a plan, shows breaks and syncs completion', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    late DatabaseService db;
    late PlannerProvider provider;
    await tester.runAsync(() async {
      db = await DatabaseService.inMemory();
      provider = PlannerProvider(
        database: db,
        gemini: GeminiService(
          transport: (_, __, ___) async => GeminiHttpResponse(
            200,
            jsonEncode({
              'candidates': [
                {
                  'finishReason': 'STOP',
                  'content': {
                    'parts': [
                      {
                        'text':
                            '{"tasks":[{"input_index":0,"duration_minutes":30}]}',
                      },
                    ],
                  },
                },
              ],
            }),
          ),
        ),
      );
      await provider.ready;
    });
    await tester.pumpWidget(AutoTaskSchedulerApp(plannerProvider: provider));
    await tester.pumpAndSettle();
    expect(find.text('Hi, Dayer.'), findsOneWidget);
    await tester.tap(find.text('Plan this day'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Review notes');
    await tester.tap(find.byTooltip('Add task'));
    await tester.pumpAndSettle();
    expect(find.text('Use Gemini'), findsNothing);
    await tester.ensureVisible(find.text('Generate plan'));
    await tester.runAsync(() async {
      await tester.tap(find.text('Generate plan'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
    expect(find.text('Review plan'), findsNothing);
    expect(find.text('Save plan'), findsNothing);
    expect(provider.currentTabIndex, 1);
    expect(provider.currentPlan!.tasks.single.durationMinutes, 30);
    expect(find.text('Take a break'), findsOneWidget);
    final checkboxes = find.byType(Checkbox);
    await tester.runAsync(() async {
      await tester.tap(checkboxes.at(1));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(provider.tasksDoneCount, 0);
    await tester.runAsync(() async {
      await tester.tap(find.byType(Checkbox).last);
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(provider.tasksDoneCount, 1);
    expect(find.text('1 of 1 completed'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    provider.dispose();
    await tester.runAsync(db.close);
  });

  testWidgets(
    'November calendar includes day 30 in its sixth row and navigates months',
    (tester) async {
      DateTime? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CalendarWidget(
              selectedDate: DateTime(2026, 11, 23),
              onDateSelected: (date) => selected = date,
            ),
          ),
        ),
      );
      expect(find.byKey(const ValueKey('date-2026-11-30')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('date-2026-11-30')));
      expect(selected, DateTime(2026, 11, 30));
      await tester.tap(find.byTooltip('Next month'));
      await tester.pumpAndSettle();
      expect(find.text('December 2026'), findsOneWidget);
    },
  );
}
