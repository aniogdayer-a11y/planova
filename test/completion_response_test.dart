import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:auto_task_scheduler/models/plan_model.dart';
import 'package:auto_task_scheduler/models/user_profile_model.dart';
import 'package:auto_task_scheduler/models/feedback_model.dart';
import 'package:auto_task_scheduler/providers/planner_provider.dart';
import 'package:auto_task_scheduler/services/database_service.dart';
import 'package:auto_task_scheduler/services/remote_planner_repository.dart';

class DelayedCompletions extends RemotePlannerRepository {
  final DatabaseService db;
  final gates = <Completer<void>>[];
  int planReads = 0;
  DelayedCompletions(this.db);
  @override
  Future<UserProfileModel> getUserProfile({DateTime? today}) =>
      db.getUserProfile(today: today);
  @override
  Future<String> getSetting(String key, {String defaultValue = ''}) =>
      db.getSetting(key, defaultValue: defaultValue);
  @override
  Future<List<FeedbackModel>> getFeedback() => db.getFeedback();
  @override
  Future<List<Map<String, dynamic>>> getWeeklyActivity({DateTime? today}) =>
      db.getWeeklyActivity(today: today);
  @override
  Future<PlanModel?> getPlanForDate(String date) {
    planReads++;
    return db.getPlanForDate(date);
  }

  @override
  Future<PlanModel> completeTask(int id, bool completed) async {
    await gates.removeAt(0).future;
    await db.toggleTaskCompletion(id, completed);
    return (await db.getPlanForDate(date))!;
  }

  @override
  Future<PlanModel> completeSlot(int id, bool completed) async {
    await gates.removeAt(0).future;
    await db.toggleSlotCompletion(id, completed);
    return (await db.getPlanForDate(date))!;
  }

  late String date;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late DatabaseService db;
  late PlannerProvider planner;
  late DelayedCompletions repo;
  setUp(() async {
    db = await DatabaseService.inMemory();
    final seed = PlannerProvider(database: db);
    await seed.ready;
    seed.preparePlanDraft();
    seed.addDraftTask('Review', duration: 30);
    seed.addDraftTask('Discussion', duration: 20);
    await seed.generateDraft(useGemini: false);
    await seed.saveDraft();
    repo = DelayedCompletions(db)..date = seed.currentPlan!.planDate;
    seed.dispose();
    planner = PlannerProvider(repository: repo);
    await planner.ready;
  });
  tearDown(() async {
    planner.dispose();
    // Let the background stats read settle before closing the test database.
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await db.close();
  });

  test(
    'rapid clicks update immediately and later responses preserve the last click',
    () async {
      final task = planner.currentPlan!.tasks.first;
      final other = planner.currentPlan!.tasks.last;
      final gates = List.generate(3, (_) => Completer<void>());
      repo.gates.addAll(gates);
      final first = planner.setTaskCompletion(task.id!, true);
      expect(planner.currentPlan!.tasks.first.isCompleted, isTrue);
      expect(
        planner.currentPlan!.scheduleSlots
            .where((s) => s.taskId == task.id)
            .every((s) => s.isCompleted),
        isTrue,
      );
      final second = planner.setTaskCompletion(task.id!, false);
      final third = planner.setTaskCompletion(other.id!, true);
      expect(planner.currentPlan!.tasks.first.isCompleted, isFalse);
      expect(planner.currentPlan!.tasks.last.isCompleted, isTrue);
      final reads = repo.planReads;
      await planner.refresh();
      expect(repo.planReads, reads);
      gates[0].complete();
      await first;
      expect(planner.currentPlan!.tasks.first.isCompleted, isFalse);
      expect(planner.currentPlan!.tasks.last.isCompleted, isTrue);
      gates[1].complete();
      await second;
      gates[2].complete();
      await third;
      expect(planner.isSyncingCompletions, isFalse);
      expect(
        repo.planReads,
        reads,
        reason: 'save response supplies the confirmed plan',
      );
      final saved = (await db.getPlanForDate(repo.date))!;
      expect(saved.tasks.first.isCompleted, isFalse);
      expect(saved.tasks.last.isCompleted, isTrue);
    },
  );

  test(
    'failed task save rolls back while a later schedule click remains visible',
    () async {
      final task = planner.currentPlan!.tasks.first;
      final otherSlot = planner.currentPlan!.scheduleSlots.last;
      final failedGate = Completer<void>(), successGate = Completer<void>();
      repo.gates.addAll([failedGate, successGate]);
      final failed = planner.setTaskCompletion(task.id!, true);
      final failure = expectLater(failed, throwsStateError);
      final success = planner.setSlotCompletion(otherSlot.id!, true);
      expect(planner.currentPlan!.scheduleSlots.last.isCompleted, isTrue);
      await Future<void>.delayed(Duration.zero);
      failedGate.completeError(StateError('offline'));
      await failure;
      expect(planner.currentPlan!.tasks.first.isCompleted, isFalse);
      expect(planner.currentPlan!.scheduleSlots.last.isCompleted, isTrue);
      successGate.complete();
      await success;
      expect(planner.currentPlan!.scheduleSlots.last.isCompleted, isTrue);
      expect(planner.currentPlan!.tasks.last.isCompleted, isTrue);
    },
  );

  test('a save response does not replace a different selected day', () async {
    final task = planner.currentPlan!.tasks.first;
    final gate = Completer<void>();
    repo.gates.add(gate);
    final write = planner.setTaskCompletion(task.id!, true);
    await planner.selectDate(planner.selectedDate.add(const Duration(days: 1)));
    expect(planner.currentPlan, isNull);
    gate.complete();
    await write;
    expect(planner.currentPlan, isNull);
    await planner.selectDate(DateTime.parse(repo.date));
    expect(planner.currentPlan!.tasks.first.isCompleted, isTrue);
  });
}
