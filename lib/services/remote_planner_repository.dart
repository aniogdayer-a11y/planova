import 'package:intl/intl.dart';
import 'dart:convert';
import '../models/feedback_model.dart';
import '../models/plan_model.dart';
import '../models/task_model.dart';
import '../models/schedule_slot_model.dart';
import '../models/user_profile_model.dart';
import 'api_client.dart';
import 'planner_repository.dart';

class RemotePlannerRepository
    implements PlannerRepository, DraftAwareRepository, AvatarRepository {
  final ApiClient api;
  final Map<String, int> _revisions = {};
  final Map<String, int> _draftRevisions = {};
  @override
  void beginDraft(String date) {
    _draftRevisions[date] = _revisions[date] ?? 0;
  }

  final Map<int, String> _tasks = {}, _slots = {};
  RemotePlannerRepository({ApiClient? client})
    : api = client ?? ApiClient.shared;
  String _today([DateTime? date]) =>
      DateFormat('yyyy-MM-dd').format(date ?? DateTime.now());
  PlanModel? _remember(Map<String, dynamic> result, String date) {
    _revisions[date] = result['revision'] as int;
    if (result['plan'] == null) return null;
    final data = result['plan'] as Map<String, dynamic>;
    final tasks = (data['tasks'] as List)
        .map((t) => TaskModel.fromMap(Map<String, dynamic>.from(t as Map)))
        .toList();
    final slots = (data['schedule_slots'] as List)
        .map(
          (s) => ScheduleSlotModel.fromMap(Map<String, dynamic>.from(s as Map)),
        )
        .toList();
    for (final task in tasks) {
      _tasks[task.id!] = date;
    }
    for (final slot in slots) {
      _slots[slot.id!] = date;
    }
    return PlanModel.fromMap(data, tasks: tasks, scheduleSlots: slots);
  }

  @override
  Future<PlanModel?> getPlanForDate(String date) async =>
      _remember(await api.request('GET', 'plans/$date'), date);
  @override
  Future<PlanModel> saveOrUpdatePlan(
    PlanModel plan,
    List<TaskModel> tasks,
  ) async {
    final result = await api.request(
      'PUT',
      'plans/${plan.planDate}',
      data: {
        'expected_revision':
            _draftRevisions[plan.planDate] ?? _revisions[plan.planDate] ?? 0,
        'plan': {
          ...plan.toMap(),
          'tasks': tasks.map((t) => t.toMap()).toList(),
        },
      },
    );
    _draftRevisions.remove(plan.planDate);
    return _remember(result, plan.planDate)!;
  }

  Future<void> _toggle(String kind, int id, bool completed) async {
    final date = (kind == 'tasks' ? _tasks : _slots)[id];
    if (date == null) {
      throw const ApiException(404, 'Refresh this plan and try again.');
    }
    final result = await api.request(
      'POST',
      '$kind/$id',
      data: {
        'completed': completed,
        'expected_revision': _revisions[date],
        'timezone_offset_minutes': DateTime.now().timeZoneOffset.inMinutes,
      },
    );
    _remember(result, date);
  }

  @override
  Future<void> toggleTaskCompletion(int id, bool completed) =>
      _toggle('tasks', id, completed);
  @override
  Future<void> toggleSlotCompletion(int id, bool completed) =>
      _toggle('slots', id, completed);
  @override
  Future<UserProfileModel> getUserProfile({DateTime? today}) async =>
      UserProfileModel.fromMap(
        (await api.request('GET', 'profile?today=${_today(today)}'))['profile']
            as Map<String, dynamic>,
      );
  @override
  Future<void> updateUserProfile(UserProfileModel profile) async {
    await api.request('PUT', 'profile', data: {'name': profile.name});
  }

  @override
  Future<void> updateAvatar(List<int>? bytes) async {
    await api.request(
      'PUT',
      'profile/avatar',
      data: {'image_base64': bytes == null ? null : base64Encode(bytes)},
    );
  }

  @override
  Future<List<Map<String, dynamic>>> getWeeklyActivity({
    DateTime? today,
  }) async {
    final result = await api.request('GET', 'activity?today=${_today(today)}');
    return (result['weekly'] as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  @override
  Future<String> getSetting(String key, {String defaultValue = ''}) async {
    final result = await api.request('GET', 'settings');
    return (result['settings'] as Map)[key] as String? ?? defaultValue;
  }

  @override
  Future<void> setSetting(String key, String value) async {
    await api.request('PUT', 'settings', data: {'key': key, 'value': value});
  }

  @override
  Future<List<FeedbackModel>> getFeedback() async {
    final result = await api.request('GET', 'feedback');
    return (result['feedback'] as List)
        .map((e) => FeedbackModel.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  @override
  Future<FeedbackModel> addFeedback(
    String content, {
    String visibility = 'public',
  }) async {
    final result = await api.request(
      'POST',
      'feedback',
      data: {'content': content, 'visibility': visibility},
    );
    return FeedbackModel.fromMap(
      Map<String, dynamic>.from(result['feedback'] as Map),
    );
  }

  @override
  Future<FeedbackModel> updateFeedback(
    String id,
    String content, {
    String visibility = 'public',
  }) async {
    final result = await api.request(
      'PUT',
      'feedback/$id',
      data: {'content': content, 'visibility': visibility},
    );
    return FeedbackModel.fromMap(
      Map<String, dynamic>.from(result['feedback'] as Map),
    );
  }

  @override
  Future<void> deleteFeedback(String id) async {
    await api.request('DELETE', 'feedback/$id');
  }

  @override
  Future<Map<String, dynamic>> toggleFeedbackLike(String id) async {
    final result = await api.request('POST', 'feedback/$id/like');
    return Map<String, dynamic>.from(result);
  }
}
