import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:auto_task_scheduler/models/plan_model.dart';
import 'package:auto_task_scheduler/models/task_model.dart';
import 'package:auto_task_scheduler/services/api_client.dart';
import 'package:auto_task_scheduler/services/remote_planner_repository.dart';

void main() {
  test(
    'a background refresh cannot advance the revision of an open draft',
    () async {
      var read = 0;
      final repo = RemotePlannerRepository(
        client: ApiClient(
          base: Uri.parse('https://test.invalid/api/'),
          client: MockClient((request) async {
            if (request.method == 'GET') {
              read++;
              return http.Response(
                jsonEncode({'plan': null, 'revision': read}),
                200,
              );
            }
            expect(jsonDecode(request.body)['expected_revision'], 1);
            return http.Response(
              '{"error":"This plan changed on another device."}',
              409,
            );
          }),
        ),
      );
      await repo.getPlanForDate('2026-11-23');
      repo.beginDraft('2026-11-23');
      await repo.getPlanForDate('2026-11-23');
      final plan = PlanModel(
        planDate: '2026-11-23',
        startTime: '9:00 AM',
        endTime: '',
        createdAt: '',
      );
      await expectLater(
        repo.saveOrUpdatePlan(plan, [
          TaskModel(title: 'Task', durationMinutes: 30),
        ]),
        throwsA(isA<ApiException>().having((e) => e.status, 'status', 409)),
      );
    },
  );

  test('concurrent slot completions use the latest plan revision', () async {
    const date = '2026-11-24';
    var revision = 1;
    final requestRevisions = <int>[];
    final plan = <String, dynamic>{
      'id': 1,
      'plan_date': date,
      'start_time': '9:00 AM',
      'has_breaks': 0,
      'break_count': 0,
      'break_duration_minutes': 0,
      'total_focus_minutes': 50,
      'end_time': '9:50 AM',
      'created_at': '2026-11-24T00:00:00.000',
      'tasks': [
        {
          'id': 11,
          'plan_id': 1,
          'title': 'Review',
          'duration_minutes': 25,
          'order_index': 0,
          'is_completed': 0,
          'completed_at': null,
        },
        {
          'id': 12,
          'plan_id': 1,
          'title': 'Discussion',
          'duration_minutes': 25,
          'order_index': 1,
          'is_completed': 0,
          'completed_at': null,
        },
      ],
      'schedule_slots': [
        {
          'id': 101,
          'plan_id': 1,
          'task_id': 11,
          'slot_type': 'focus',
          'title': 'Review',
          'subtitle': 'Focus session 1',
          'start_time': '9:00 AM',
          'end_time': '9:25 AM',
          'duration_minutes': 25,
          'order_index': 0,
          'is_completed': 0,
        },
        {
          'id': 102,
          'plan_id': 1,
          'task_id': 12,
          'slot_type': 'focus',
          'title': 'Discussion',
          'subtitle': 'Focus session 1',
          'start_time': '9:25 AM',
          'end_time': '9:50 AM',
          'duration_minutes': 25,
          'order_index': 1,
          'is_completed': 0,
        },
      ],
    };
    final repo = RemotePlannerRepository(
      client: ApiClient(
        base: Uri.parse('https://test.invalid/api/'),
        client: MockClient((request) async {
          if (request.method == 'GET') {
            return http.Response(
              jsonEncode({'plan': plan, 'revision': revision}),
              200,
            );
          }

          final body = jsonDecode(request.body) as Map<String, dynamic>;
          final expectedRevision = body['expected_revision'] as int;
          requestRevisions.add(expectedRevision);
          await Future<void>.delayed(const Duration(milliseconds: 5));
          if (expectedRevision != revision) {
            return http.Response(
              '{"error":"This plan changed on another device."}',
              409,
            );
          }

          final slotId = int.parse(request.url.pathSegments.last);
          final slots = (plan['schedule_slots'] as List)
              .cast<Map<String, dynamic>>();
          final slot = slots.firstWhere((item) => item['id'] == slotId);
          final completed = body['completed'] as bool;
          slot['is_completed'] = completed ? 1 : 0;
          final taskId = slot['task_id'] as int;
          final taskSlots = slots.where((item) => item['task_id'] == taskId);
          final taskCompleted = taskSlots.every(
            (item) => item['is_completed'] == 1,
          );
          final tasks = (plan['tasks'] as List).cast<Map<String, dynamic>>();
          final task = tasks.firstWhere((item) => item['id'] == taskId);
          task['is_completed'] = taskCompleted ? 1 : 0;
          task['completed_at'] = taskCompleted
              ? '2026-11-24T10:00:00.000'
              : null;
          revision++;
          return http.Response(
            jsonEncode({'plan': plan, 'revision': revision}),
            200,
          );
        }),
      ),
    );

    await repo.getPlanForDate(date);
    await Future.wait([
      repo.toggleSlotCompletion(101, true),
      repo.toggleSlotCompletion(102, true),
    ]);

    expect(requestRevisions, [1, 2]);
    final saved = (await repo.getPlanForDate(date))!;
    expect(saved.scheduleSlots.every((slot) => slot.isCompleted), isTrue);
    expect(saved.tasks.every((task) => task.isCompleted), isTrue);
  });
}
