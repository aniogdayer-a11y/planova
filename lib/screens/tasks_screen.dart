import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../providers/planner_provider.dart';
import '../widgets/page_layout.dart';
import '../widgets/planner_actions.dart';
import '../widgets/timeline_slot_card.dart';
import 'plan_day_screen.dart';

class TasksScreen extends StatelessWidget {
  const TasksScreen({super.key});
  Future<void> _delete(
    BuildContext context,
    PlannerProvider planner,
    int id,
    String title,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete task?'),
        content: Text(title),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await plannerAction(context, () => planner.deleteTask(id));
    }
  }

  void _edit(BuildContext context, PlannerProvider planner) {
    planner.preparePlanDraft();
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PlanDayScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final planner = context.watch<PlannerProvider>();
    final plan = planner.currentPlan;
    return LayoutBuilder(
      builder: (context, constraints) {
        final tasks = plan == null
            ? const SizedBox.shrink()
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${planner.tasksDoneCount} of ${plan.tasks.length} completed',
                        ),
                      ),
                      Text('${plan.totalFocusMinutes} min focus'),
                    ],
                  ),
                  const SizedBox(height: 12),
                  LinearProgressIndicator(
                    value: plan.tasks.isEmpty
                        ? 0
                        : planner.tasksDoneCount / plan.tasks.length,
                    minHeight: 4,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  const SizedBox(height: 20),
                  Card(
                    child: Column(
                      children: plan.tasks
                          .map(
                            (task) => CheckboxListTile(
                              key: ValueKey('task-${task.id}'),
                              value: task.isCompleted,
                              onChanged: planner.isSaving
                                  ? null
                                  : (value) {
                                      if (value == null) return;
                                      plannerAction(
                                        context,
                                        () => planner.setTaskCompletion(
                                          task.id!,
                                          value,
                                        ),
                                      );
                                    },
                              controlAffinity: ListTileControlAffinity.leading,
                              secondary: IconButton(
                                tooltip: 'Delete ${task.title}',
                                icon: const Icon(
                                  Icons.delete_outline,
                                  size: 20,
                                ),
                                onPressed: planner.isSaving
                                    ? null
                                    : () => _delete(
                                        context,
                                        planner,
                                        task.id!,
                                        task.title,
                                      ),
                              ),
                              title: Text(
                                task.title,
                                style: TextStyle(
                                  fontSize: 15,
                                  decoration: task.isCompleted
                                      ? TextDecoration.lineThrough
                                      : null,
                                ),
                              ),
                              subtitle: Text('${task.durationMinutes} min'),
                              dense: true,
                            ),
                          )
                          .toList(),
                    ),
                  ),
                  const SizedBox(height: 20),
                  OutlinedButton(
                    onPressed: planner.isSyncingCompletions || planner.isSaving
                        ? null
                        : () => _edit(context, planner),
                    child: const Text('Edit plan'),
                  ),
                ],
              );
        final timeline = plan == null
            ? const SizedBox.shrink()
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Schedule',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      Text('Ends ${planner.displayTime(plan.endTime)}'),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ...plan.scheduleSlots.map(
                    (slot) => TimelineSlotCard(
                      key: ValueKey('slot-${slot.id}'),
                      slot: slot,
                      startLabel: planner.displayTime(slot.startTime),
                      endLabel: planner.displayTime(slot.endTime),
                      onChanged: planner.isSaving
                          ? null
                          : (value) => plannerAction(
                              context,
                              () => planner.setSlotCompletion(slot.id!, value),
                            ),
                    ),
                  ),
                ],
              );
        return PageLayout(
          title: 'Tasks',
          subtitle: DateFormat('EEE, MMMM d').format(planner.selectedDate),
          children: [
            if (planner.isLoadingPlan)
              const Center(child: CircularProgressIndicator())
            else if (plan == null) ...[
              const Text('No plan for this day yet.'),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => _edit(context, planner),
                child: const Text('Add a plan'),
              ),
            ] else if (constraints.maxWidth >= 1000)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 4, child: tasks),
                  const SizedBox(width: 32),
                  Expanded(flex: 6, child: timeline),
                ],
              )
            else ...[
              tasks,
              const SizedBox(height: 28),
              timeline,
            ],
          ],
        );
      },
    );
  }
}
