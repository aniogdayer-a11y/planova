enum SlotType { focus, breakSlot }

class ScheduleSlotModel {
  final int? id;
  final int? planId;
  final int? taskId;
  final SlotType slotType;
  final String title;
  final String subtitle;
  final String startTime;
  final String endTime;
  final int durationMinutes;
  final int orderIndex;
  final bool isCompleted;

  ScheduleSlotModel({
    this.id,
    this.planId,
    this.taskId,
    required this.slotType,
    required this.title,
    required this.subtitle,
    required this.startTime,
    required this.endTime,
    required this.durationMinutes,
    this.orderIndex = 0,
    this.isCompleted = false,
  });

  ScheduleSlotModel copyWith({
    int? id,
    int? planId,
    int? taskId,
    SlotType? slotType,
    String? title,
    String? subtitle,
    String? startTime,
    String? endTime,
    int? durationMinutes,
    int? orderIndex,
    bool? isCompleted,
  }) {
    return ScheduleSlotModel(
      id: id ?? this.id,
      planId: planId ?? this.planId,
      taskId: taskId ?? this.taskId,
      slotType: slotType ?? this.slotType,
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      durationMinutes: durationMinutes ?? this.durationMinutes,
      orderIndex: orderIndex ?? this.orderIndex,
      isCompleted: isCompleted ?? this.isCompleted,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'plan_id': planId,
      'task_id': taskId,
      'slot_type': slotType == SlotType.focus ? 'focus' : 'break',
      'title': title,
      'subtitle': subtitle,
      'start_time': startTime,
      'end_time': endTime,
      'duration_minutes': durationMinutes,
      'order_index': orderIndex,
      'is_completed': isCompleted ? 1 : 0,
    };
  }

  factory ScheduleSlotModel.fromMap(Map<String, dynamic> map) {
    return ScheduleSlotModel(
      id: map['id'] as int?,
      planId: map['plan_id'] as int?,
      taskId: map['task_id'] as int?,
      slotType: (map['slot_type'] as String?) == 'break'
          ? SlotType.breakSlot
          : SlotType.focus,
      title: map['title'] as String,
      subtitle: (map['subtitle'] as String?) ?? '',
      startTime: map['start_time'] as String,
      endTime: map['end_time'] as String,
      durationMinutes: (map['duration_minutes'] as int?) ?? 25,
      orderIndex: (map['order_index'] as int?) ?? 0,
      isCompleted: (map['is_completed'] as int? ?? 0) == 1,
    );
  }
}
