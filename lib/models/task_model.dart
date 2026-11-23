class TaskModel {
  final int? id;
  final int? planId;
  final String title;
  final int durationMinutes;
  final int orderIndex;
  final bool isCompleted;
  final String? completedAt;

  TaskModel({
    this.id,
    this.planId,
    required this.title,
    this.durationMinutes = 50,
    this.orderIndex = 0,
    this.isCompleted = false,
    this.completedAt,
  });

  TaskModel copyWith({
    int? id,
    int? planId,
    String? title,
    int? durationMinutes,
    int? orderIndex,
    bool? isCompleted,
    String? completedAt,
  }) {
    return TaskModel(
      id: id ?? this.id,
      planId: planId ?? this.planId,
      title: title ?? this.title,
      durationMinutes: durationMinutes ?? this.durationMinutes,
      orderIndex: orderIndex ?? this.orderIndex,
      isCompleted: isCompleted ?? this.isCompleted,
      completedAt: isCompleted == false
          ? null
          : (completedAt ?? this.completedAt),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'plan_id': planId,
      'title': title,
      'duration_minutes': durationMinutes,
      'order_index': orderIndex,
      'is_completed': isCompleted ? 1 : 0,
      'completed_at': completedAt,
    };
  }

  factory TaskModel.fromMap(Map<String, dynamic> map) {
    return TaskModel(
      id: map['id'] as int?,
      planId: map['plan_id'] as int?,
      title: map['title'] as String,
      durationMinutes: (map['duration_minutes'] as int?) ?? 50,
      orderIndex: (map['order_index'] as int?) ?? 0,
      isCompleted: (map['is_completed'] as int? ?? 0) == 1,
      completedAt: map['completed_at'] as String?,
    );
  }
}
