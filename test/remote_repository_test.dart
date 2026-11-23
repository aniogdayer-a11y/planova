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
}
