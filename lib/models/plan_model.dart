import 'task_model.dart';
import 'schedule_slot_model.dart';

class PlanModel {
  final int? id;
  final String planDate; // ISO format YYYY-MM-DD
  final String startTime; // e.g. "9:00 AM"
  final bool hasBreaks;
  final int breakCount; // e.g. 1
  final int breakDurationMinutes; // e.g. 5
  final int totalFocusMinutes;
  final String endTime; // e.g. "10:25 AM"
  final String createdAt;
  final List<TaskModel> tasks;
  final List<ScheduleSlotModel> scheduleSlots;

  PlanModel({
    this.id,
    required this.planDate,
    required this.startTime,
    this.hasBreaks = true,
    this.breakCount = 1,
    this.breakDurationMinutes = 5,
    this.totalFocusMinutes = 80,
    required this.endTime,
    required this.createdAt,
    this.tasks = const [],
    this.scheduleSlots = const [],
  });

  PlanModel copyWith({
    int? id,
    String? planDate,
    String? startTime,
    bool? hasBreaks,
    int? breakCount,
    int? breakDurationMinutes,
    int? totalFocusMinutes,
    String? endTime,
    String? createdAt,
    List<TaskModel>? tasks,
    List<ScheduleSlotModel>? scheduleSlots,
  }) {
    return PlanModel(
      id: id ?? this.id,
      planDate: planDate ?? this.planDate,
      startTime: startTime ?? this.startTime,
      hasBreaks: hasBreaks ?? this.hasBreaks,
      breakCount: breakCount ?? this.breakCount,
      breakDurationMinutes: breakDurationMinutes ?? this.breakDurationMinutes,
      totalFocusMinutes: totalFocusMinutes ?? this.totalFocusMinutes,
      endTime: endTime ?? this.endTime,
      createdAt: createdAt ?? this.createdAt,
      tasks: tasks ?? this.tasks,
      scheduleSlots: scheduleSlots ?? this.scheduleSlots,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'plan_date': planDate,
      'start_time': startTime,
      'has_breaks': hasBreaks ? 1 : 0,
      'break_count': breakCount,
      'break_duration_minutes': breakDurationMinutes,
      'total_focus_minutes': totalFocusMinutes,
      'end_time': endTime,
      'created_at': createdAt,
    };
  }

  factory PlanModel.fromMap(
    Map<String, dynamic> map, {
    List<TaskModel> tasks = const [],
    List<ScheduleSlotModel> scheduleSlots = const [],
  }) {
    return PlanModel(
      id: map['id'] as int?,
      planDate: map['plan_date'] as String,
      startTime: map['start_time'] as String,
      hasBreaks: (map['has_breaks'] as int? ?? 1) == 1,
      breakCount: (map['break_count'] as int?) ?? 1,
      breakDurationMinutes: (map['break_duration_minutes'] as int?) ?? 5,
      totalFocusMinutes: (map['total_focus_minutes'] as int?) ?? 80,
      endTime: (map['end_time'] as String?) ?? '10:25 AM',
      createdAt:
          (map['created_at'] as String?) ?? DateTime.now().toIso8601String(),
      tasks: tasks,
      scheduleSlots: scheduleSlots,
    );
  }
}
