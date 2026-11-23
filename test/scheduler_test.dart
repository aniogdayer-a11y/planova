import 'package:flutter_test/flutter_test.dart';
import 'package:auto_task_scheduler/models/task_model.dart';
import 'package:auto_task_scheduler/models/schedule_slot_model.dart';
import 'package:auto_task_scheduler/services/scheduler_service.dart';

void main() {
  group('SchedulerService Tests matching Figma Specifications', () {
    test('1 task with 1 break of 5 minutes: Pubmat (50 min)', () {
      final tasks = [
        TaskModel(id: 1, title: 'Pubmat', durationMinutes: 50, orderIndex: 0),
      ];

      final result = SchedulerService.generateSchedule(
        tasks: tasks,
        startTimeStr: '9:00 AM',
        hasBreaks: true,
        breakCount: 1,
        breakDurationMinutes: 5,
      );

      expect(result.slots.length, 3);
      // Slot 1: Focus 1 (25m)
      expect(result.slots[0].slotType, SlotType.focus);
      expect(result.slots[0].startTime, '9:00 AM');
      expect(result.slots[0].endTime, '9:25 AM');
      expect(result.slots[0].durationMinutes, 25);

      // Slot 2: Break (5m)
      expect(result.slots[1].slotType, SlotType.breakSlot);
      expect(result.slots[1].startTime, '9:25 AM');
      expect(result.slots[1].endTime, '9:30 AM');
      expect(result.slots[1].durationMinutes, 5);

      // Slot 3: Focus 2 (25m)
      expect(result.slots[2].slotType, SlotType.focus);
      expect(result.slots[2].startTime, '9:30 AM');
      expect(result.slots[2].endTime, '9:55 AM');
      expect(result.slots[2].durationMinutes, 25);

      expect(result.endTime, '9:55 AM');
      expect(result.totalFocusMinutes, 50);
      expect(result.summaryText, contains('Ends 9:55 AM'));
    });

    test(
      '2 tasks with 1 break of 5 minutes: Pubmat (50m) + Review notes (30m)',
      () {
        final tasks = [
          TaskModel(id: 1, title: 'Pubmat', durationMinutes: 50, orderIndex: 0),
          TaskModel(
            id: 2,
            title: 'Review notes',
            durationMinutes: 30,
            orderIndex: 1,
          ),
        ];

        final result = SchedulerService.generateSchedule(
          tasks: tasks,
          startTimeStr: '9:00 AM',
          hasBreaks: true,
          breakCount: 1,
          breakDurationMinutes: 5,
        );

        expect(result.slots.length, 4);
        // Focus 1: 9:00 - 9:25 AM
        expect(result.slots[0].startTime, '9:00 AM');
        expect(result.slots[0].endTime, '9:25 AM');

        // Break: 9:25 - 9:30 AM
        expect(result.slots[1].startTime, '9:25 AM');
        expect(result.slots[1].endTime, '9:30 AM');

        // Focus 2: 9:30 - 9:55 AM
        expect(result.slots[2].startTime, '9:30 AM');
        expect(result.slots[2].endTime, '9:55 AM');

        // Task 2: 9:55 - 10:25 AM
        expect(result.slots[3].title, 'Review notes');
        expect(result.slots[3].startTime, '9:55 AM');
        expect(result.slots[3].endTime, '10:25 AM');

        expect(result.endTime, '10:25 AM');
        expect(result.totalFocusMinutes, 80);
        expect(result.summaryText, contains('Ends 10:25 AM'));
      },
    );

    test('1 task without breaks: Pubmat (50 min)', () {
      final tasks = [
        TaskModel(id: 1, title: 'Pubmat', durationMinutes: 50, orderIndex: 0),
      ];

      final result = SchedulerService.generateSchedule(
        tasks: tasks,
        startTimeStr: '9:00 AM',
        hasBreaks: false,
      );

      expect(result.slots.length, 1);
      expect(result.slots[0].startTime, '9:00 AM');
      expect(result.slots[0].endTime, '9:50 AM');
      expect(result.endTime, '9:50 AM');
      expect(result.summaryText, contains('No breaks • Ends 9:50 AM'));
    });

    test('2 tasks without breaks: Pubmat (50m) + Review notes (30m)', () {
      final tasks = [
        TaskModel(id: 1, title: 'Pubmat', durationMinutes: 50, orderIndex: 0),
        TaskModel(
          id: 2,
          title: 'Review notes',
          durationMinutes: 30,
          orderIndex: 1,
        ),
      ];

      final result = SchedulerService.generateSchedule(
        tasks: tasks,
        startTimeStr: '9:00 AM',
        hasBreaks: false,
      );

      expect(result.slots.length, 2);
      expect(result.slots[0].startTime, '9:00 AM');
      expect(result.slots[0].endTime, '9:50 AM');
      expect(result.slots[1].startTime, '9:50 AM');
      expect(result.slots[1].endTime, '10:20 AM');
      expect(result.endTime, '10:20 AM');
      expect(result.summaryText, contains('No breaks • Ends 10:20 AM'));
    });
  });
  test(
    'short tasks still receive the requested breaks without zero-length focus',
    () {
      final result = SchedulerService.generateSchedule(
        tasks: [
          TaskModel(id: 1, title: 'Quick task', durationMinutes: 10),
          TaskModel(id: 2, title: 'Next', durationMinutes: 20),
        ],
        startTimeStr: '9:00 AM',
        hasBreaks: true,
        breakCount: 3,
        breakDurationMinutes: 5,
      );
      expect(
        result.slots.where((s) => s.slotType == SlotType.breakSlot).length,
        3,
      );
      expect(result.slots.every((s) => s.durationMinutes > 0), isTrue);
      expect(
        result.slots
            .where((s) => s.slotType == SlotType.focus)
            .fold<int>(0, (sum, slot) => sum + slot.durationMinutes),
        30,
      );
      expect(result.endTime, '9:45 AM');
    },
  );

  test('invalid time, duration and overnight plans are rejected', () {
    for (final time in ['not a time', '25:00', '9:99 AM']) {
      expect(
        () => SchedulerService.generateSchedule(
          tasks: [TaskModel(title: 'Task', durationMinutes: 20)],
          startTimeStr: time,
          hasBreaks: false,
        ),
        throwsFormatException,
      );
    }
    expect(
      () => SchedulerService.generateSchedule(
        tasks: [TaskModel(title: 'Task', durationMinutes: 0)],
        startTimeStr: '9:00 AM',
        hasBreaks: false,
      ),
      throwsFormatException,
    );
    expect(
      () => SchedulerService.generateSchedule(
        tasks: [TaskModel(title: 'Task', durationMinutes: 60)],
        startTimeStr: '11:30 PM',
        hasBreaks: false,
      ),
      throwsFormatException,
    );
  });
}
