import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:auto_task_scheduler/providers/planner_provider.dart';
import 'package:auto_task_scheduler/services/database_service.dart';
import 'package:auto_task_scheduler/services/gemini_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late DatabaseService db;
  setUp(() async {
    db = await DatabaseService.inMemory();
  });
  tearDown(() => db.close());

  test('Generated plans are automatically saved and opened in Tasks', () async {
    final gemini = GeminiService(
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
                        '{"tasks":[{"input_index":0,"duration_minutes":45}]}',
                  },
                ],
              },
            },
          ],
        }),
      ),
    );
    final provider = PlannerProvider(database: db, gemini: gemini);
    await provider.ready;
    provider.preparePlanDraft();
    provider.addDraftTask('Read chapter');
    await provider.generateAndSaveDraft();
    expect(provider.draftTasks.single.durationMinutes, 45);
    expect(provider.currentTabIndex, 1);
    expect(await (await db.database).query('plans'), hasLength(1));
    expect(provider.currentPlan!.tasks.single.title, 'Read chapter');
    final settings = await (await db.database).query('settings');
    expect(jsonEncode(settings), isNot(contains('session-secret')));
    provider.dispose();
  });

  test(
    'failed generation leaves the saved plan and current draft intact',
    () async {
      final provider = PlannerProvider(
        database: db,
        gemini: GeminiService(
          transport: (_, __, ___) async => const GeminiHttpResponse(429, '{}'),
        ),
      );
      await provider.ready;
      provider.preparePlanDraft();
      provider.addDraftTask('Task');
      await provider.generateDraft(useGemini: false);
      await provider.saveDraft();
      final id = provider.currentPlan!.id;
      provider.preparePlanDraft();
      provider.addDraftTask('New task');
      await expectLater(
        provider.generateAndSaveDraft(),
        throwsA(isA<GeminiException>()),
      );
      expect(provider.isGenerating, isFalse);
      expect(provider.draftTasks.length, 2);
      expect(provider.currentPlan!.id, id);
      expect(provider.currentPlan!.tasks.length, 1);
      provider.dispose();
    },
  );

  test(
    'time preference formats existing schedules and persists across providers',
    () async {
      final provider = PlannerProvider(database: db);
      await provider.ready;
      expect(provider.displayTime('2:30 PM'), '2:30 PM');
      await provider.toggleTimeFormat(true);
      expect(provider.displayTime('2:30 PM'), '14:30');
      final reopened = PlannerProvider(database: db);
      await reopened.ready;
      expect(reopened.is24Hour, isTrue);
      expect(reopened.displayTime('9:00 AM'), '09:00');
      provider.dispose();
      reopened.dispose();
    },
  );
}
