import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:auto_task_scheduler/models/task_model.dart';
import 'package:auto_task_scheduler/models/plan_model.dart';
import 'package:auto_task_scheduler/models/schedule_slot_model.dart';
import 'package:auto_task_scheduler/services/database_service.dart';

PlanModel planFor(String date, {bool breaks = true}) => PlanModel(
  planDate: date,
  startTime: '9:00 AM',
  hasBreaks: breaks,
  breakCount: breaks ? 1 : 0,
  breakDurationMinutes: breaks ? 5 : 0,
  totalFocusMinutes: 0,
  endTime: '',
  createdAt: DateTime.now().toIso8601String(),
);
List<TaskModel> exampleTasks() => [
  TaskModel(title: 'Pubmat', durationMinutes: 50),
  TaskModel(title: 'Review notes', durationMinutes: 30, orderIndex: 1),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late DatabaseService service;
  setUp(() async {
    service = await DatabaseService.inMemory();
  });
  tearDown(() async {
    await service.close();
  });
  final date = DateFormat('yyyy-MM-dd').format(DateTime.now());

  test('fresh database has no pretend tasks or activity', () async {
    expect(await service.getPlanForDate(date), isNull);
    expect((await service.getUserProfile()).streakCount, 0);
    expect(
      (await service.getWeeklyActivity()).every(
        (d) => d['tasks_completed'] == 0,
      ),
      isTrue,
    );
  });

  test('plan round trips with ordered focus and break slots', () async {
    final saved = await service.saveOrUpdatePlan(planFor(date), exampleTasks());
    final retrieved = (await service.getPlanForDate(date))!;
    expect(retrieved.id, saved.id);
    expect(retrieved.tasks.map((t) => t.title), ['Pubmat', 'Review notes']);
    expect(retrieved.scheduleSlots.length, 4);
    expect(retrieved.scheduleSlots[1].slotType, SlotType.breakSlot);
    expect(retrieved.scheduleSlots[1].taskId, isNull);
    expect(retrieved.endTime, '10:25 AM');
  });

  test(
    'all focus sessions complete the task; undo updates activity and streak',
    () async {
      final saved = await service.saveOrUpdatePlan(
        planFor(date),
        exampleTasks(),
      );
      final focus = saved.scheduleSlots
          .where((s) => s.taskId == saved.tasks.first.id)
          .toList();
      await service.toggleSlotCompletion(focus.first.id!, true);
      expect(
        (await service.getPlanForDate(date))!.tasks.first.isCompleted,
        isFalse,
      );
      await service.toggleSlotCompletion(focus.last.id!, true);
      final completed = (await service.getPlanForDate(date))!.tasks.first;
      expect(completed.isCompleted, isTrue);
      expect(completed.completedAt, isNotNull);
      expect((await service.getWeeklyActivity()).last['tasks_completed'], 1);
      expect(await service.getStreak(), 1);
      await service.toggleSlotCompletion(focus.first.id!, false);
      expect(
        (await service.getPlanForDate(date))!.tasks.first.completedAt,
        isNull,
      );
      expect((await service.getWeeklyActivity()).last['tasks_completed'], 0);
      expect(await service.getStreak(), 0);
    },
  );

  test('task checkbox syncs focus slots without completing breaks', () async {
    final saved = await service.saveOrUpdatePlan(planFor(date), exampleTasks());
    await service.toggleTaskCompletion(saved.tasks.first.id!, true);
    final updated = (await service.getPlanForDate(date))!;
    expect(
      updated.scheduleSlots
          .where((s) => s.taskId == saved.tasks.first.id)
          .every((s) => s.isCompleted),
      isTrue,
    );
    expect(
      updated.scheduleSlots
          .firstWhere((s) => s.slotType == SlotType.breakSlot)
          .isCompleted,
      isFalse,
    );
  });

  test(
    'editing an unchanged plan preserves partial session progress',
    () async {
      final saved = await service.saveOrUpdatePlan(
        planFor(date),
        exampleTasks(),
      );
      await service.toggleSlotCompletion(saved.scheduleSlots.first.id!, true);
      final current = (await service.getPlanForDate(date))!;
      await service.saveOrUpdatePlan(planFor(date), current.tasks);
      final updated = (await service.getPlanForDate(date))!;
      expect(updated.scheduleSlots.first.isCompleted, isTrue);
      expect(updated.tasks.first.isCompleted, isFalse);
    },
  );

  test('failed save rolls back deleted tasks and slots', () async {
    final saved = await service.saveOrUpdatePlan(planFor(date), exampleTasks());
    final db = await service.database;
    await db.execute(
      "CREATE TRIGGER reject_tasks BEFORE INSERT ON tasks BEGIN SELECT RAISE(ABORT, 'test failure'); END",
    );
    await expectLater(
      service.saveOrUpdatePlan(planFor(date), [
        TaskModel(title: 'Replacement', durationMinutes: 20),
      ]),
      throwsA(anything),
    );
    final recovered = (await service.getPlanForDate(date))!;
    expect(recovered.id, saved.id);
    expect(recovered.tasks.map((t) => t.title), ['Pubmat', 'Review notes']);
    expect(recovered.scheduleSlots.length, 4);
  });

  test('concurrent saves create only one plan for a date', () async {
    await Future.wait([
      service.saveOrUpdatePlan(planFor(date), exampleTasks()),
      service.saveOrUpdatePlan(planFor(date), exampleTasks()),
    ]);
    final rows = await (await service.database).query(
      'plans',
      where: 'plan_date = ?',
      whereArgs: [date],
    );
    expect(rows.length, 1);
  });

  test('foreign keys cascade when a plan is deleted', () async {
    final saved = await service.saveOrUpdatePlan(planFor(date), exampleTasks());
    final db = await service.database;
    expect((await db.rawQuery('PRAGMA foreign_keys')).first.values.first, 1);
    await db.delete('plans', where: 'id = ?', whereArgs: [saved.id]);
    expect(await db.query('tasks'), isEmpty);
    expect(await db.query('schedule_slots'), isEmpty);
  });

  test(
    'weekly activity follows completion dates; streak allows yesterday',
    () async {
      final now = DateTime.now();
      for (final offset in [1, 2, 4]) {
        final day = DateTime(now.year, now.month, now.day - offset);
        final dayStr = DateFormat('yyyy-MM-dd').format(day);
        final saved = await service.saveOrUpdatePlan(
          planFor(dayStr, breaks: false),
          [TaskModel(title: 'Task', durationMinutes: 20)],
        );
        await (await service.database).update(
          'tasks',
          {'is_completed': 1, 'completed_at': day.toIso8601String()},
          where: 'id = ?',
          whereArgs: [saved.tasks.first.id],
        );
      }
      expect(await service.getStreak(), 2);
      final weekly = await service.getWeeklyActivity();
      expect(weekly.length, 7);
      expect(weekly.last['tasks_completed'], 0);
      expect(weekly[5]['tasks_completed'], 1);
    },
  );
  test('version 1 upgrade preserves plans, progress and preferences', () async {
    final folder = Directory('build/test_databases');
    await folder.create(recursive: true);
    final file = File(
      '${folder.path}/migration_${DateTime.now().microsecondsSinceEpoch}.db',
    );
    var legacy = await DatabaseService.openForTesting(path: file.absolute.path);
    final saved = await legacy.saveOrUpdatePlan(planFor(date), exampleTasks());
    await legacy.toggleTaskCompletion(saved.tasks.first.id!, true);
    await legacy.setSetting('time_format', '24-hour');
    final raw = await legacy.database;
    await raw.execute('DROP INDEX tasks_plan');
    await raw.execute('DROP INDEX slots_plan');
    await raw.execute('PRAGMA user_version = 1');
    await legacy.close();
    legacy = await DatabaseService.openForTesting(path: file.absolute.path);
    try {
      final restored = (await legacy.getPlanForDate(date))!;
      expect(restored.tasks.first.isCompleted, isTrue);
      expect(restored.scheduleSlots.length, 4);
      expect(await legacy.getSetting('time_format'), '24-hour');
      expect(
        (await (await legacy.database).rawQuery(
          'PRAGMA user_version',
        )).first.values.first,
        2,
      );
    } finally {
      await legacy.close();
      await file.delete();
    }
  });
}
