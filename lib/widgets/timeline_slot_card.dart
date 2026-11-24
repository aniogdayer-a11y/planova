import 'package:flutter/material.dart';
import '../models/schedule_slot_model.dart';
import '../theme/app_colors.dart';

class TimelineSlotCard extends StatelessWidget {
  final ScheduleSlotModel slot;
  final ValueChanged<bool>? onChanged;
  final String? startLabel;
  final String? endLabel;
  const TimelineSlotCard({
    super.key,
    required this.slot,
    this.onChanged,
    this.startLabel,
    this.endLabel,
  });
  @override
  Widget build(BuildContext context) {
    final isBreak = slot.slotType == SlotType.breakSlot;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isBreak ? AppColors.breakBadgeBg : AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: isBreak
            ? const SizedBox(
                width: 40,
                child: Icon(Icons.coffee_outlined, size: 22),
              )
            : onChanged == null
            ? const SizedBox(
                width: 40,
                child: Icon(Icons.circle_outlined, size: 20),
              )
            : Checkbox(
                value: slot.isCompleted,
                onChanged: (value) {
                  if (value != null) onChanged!(value);
                },
                semanticLabel: 'Complete ${slot.title}, ${slot.subtitle}',
              ),
        title: Text(
          slot.title,
          style: TextStyle(
            fontSize: 16,
            decoration: slot.isCompleted ? TextDecoration.lineThrough : null,
          ),
        ),
        subtitle: Text(
          '${startLabel ?? slot.startTime} - ${endLabel ?? slot.endTime} | ${slot.durationMinutes} min',
          style: const TextStyle(fontSize: 14),
        ),
      ),
    );
  }
}
