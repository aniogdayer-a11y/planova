import 'dart:math' as math;
import 'package:intl/intl.dart';
import '../models/task_model.dart';
import '../models/schedule_slot_model.dart';

class ScheduleResult {
  final List<ScheduleSlotModel> slots;
  final String endTime;
  final int totalFocusMinutes;
  final String summaryText;
  ScheduleResult({
    required this.slots,
    required this.endTime,
    required this.totalFocusMinutes,
    required this.summaryText,
  });
}

class SchedulerService {
  static const maxTasks = 200;
  static DateTime parseTimeString(String value, {DateTime? baseDate}) {
    final date = baseDate ?? DateTime.now();
    final text = value.trim().toUpperCase();
    final DateTime parsed;
    if (RegExp(r'^\d{1,2}:\d{2} (AM|PM)$').hasMatch(text)) {
      parsed = DateFormat('h:mm a').parseStrict(text);
    } else if (RegExp(r'^\d{2}:\d{2}$').hasMatch(text)) {
      parsed = DateFormat('HH:mm').parseStrict(text);
    } else {
      throw const FormatException('Choose a valid start time.');
    }
    return DateTime(
      date.year,
      date.month,
      date.day,
      parsed.hour,
      parsed.minute,
    );
  }

  static String formatTime(DateTime time, {bool is24Hour = false}) =>
      DateFormat(is24Hour ? 'HH:mm' : 'h:mm a').format(time);

  static ScheduleResult generateSchedule({
    required List<TaskModel> tasks,
    required String startTimeStr,
    required bool hasBreaks,
    int breakCount = 1,
    int breakDurationMinutes = 5,
    bool is24Hour = false,
  }) {
    var current = parseTimeString(startTimeStr);
    if (tasks.isEmpty) throw const FormatException('Add at least one task.');
    if (tasks.length > maxTasks ||
        tasks.any(
          (t) =>
              t.title.trim().isEmpty ||
              t.title.length > 200 ||
              t.durationMinutes < 1 ||
              t.durationMinutes > 480,
        )) {
      throw const FormatException(
        'Use up to 200 tasks, each between 1 and 480 minutes.',
      );
    }
    final total = tasks.fold(0, (sum, task) => sum + task.durationMinutes);
    final breaks = hasBreaks ? breakCount : 0;
    if (breaks < 0 ||
        breaks > 3 ||
        (hasBreaks &&
            (breakDurationMinutes < 1 || breakDurationMinutes > 60)) ||
        total <= breaks) {
      throw const FormatException(
        'Choose up to 3 breaks and leave time for focus sessions.',
      );
    }
    final minutes = total + breaks * breakDurationMinutes;
    if (current.hour * 60 + current.minute + minutes > 1440) {
      throw const FormatException(
        'This plan goes past midnight. Start earlier or shorten your tasks.',
      );
    }
    final slots = <ScheduleSlotModel>[];
    // Use 25-minute focus intervals, shortening them when a brief plan needs more breaks.
    final interval = breaks == 0 ? total : math.min(25, total ~/ (breaks + 1));
    var focusSoFar = 0;
    var breaksUsed = 0;
    for (final task in tasks) {
      var remaining = task.durationMinutes;
      var session = 0;
      while (remaining > 0) {
        final untilBreak = breaksUsed < breaks
            ? interval * (breaksUsed + 1) - focusSoFar
            : remaining;
        final duration = math.min(remaining, untilBreak);
        final end = current.add(Duration(minutes: duration));
        slots.add(
          ScheduleSlotModel(
            taskId: task.id,
            slotType: SlotType.focus,
            title: task.title,
            subtitle: 'Focus session ${++session}',
            startTime: formatTime(current, is24Hour: is24Hour),
            endTime: formatTime(end, is24Hour: is24Hour),
            durationMinutes: duration,
            orderIndex: slots.length,
            isCompleted: task.isCompleted,
          ),
        );
        current = end;
        remaining -= duration;
        focusSoFar += duration;
        if (breaksUsed < breaks && focusSoFar == interval * (breaksUsed + 1)) {
          final end = current.add(Duration(minutes: breakDurationMinutes));
          slots.add(
            ScheduleSlotModel(
              slotType: SlotType.breakSlot,
              title: 'Take a break',
              subtitle: 'Break',
              startTime: formatTime(current, is24Hour: is24Hour),
              endTime: formatTime(end, is24Hour: is24Hour),
              durationMinutes: breakDurationMinutes,
              orderIndex: slots.length,
            ),
          );
          current = end;
          breaksUsed++;
        }
      }
    }
    final endTime = formatTime(current, is24Hour: is24Hour);
    final breakText = breaks == 0
        ? 'No breaks'
        : '$breaks break${breaks == 1 ? '' : 's'}, $breakDurationMinutes minutes';
    return ScheduleResult(
      slots: slots,
      endTime: endTime,
      totalFocusMinutes: total,
      summaryText: '$breakText \u2022 Ends $endTime',
    );
  }
}
