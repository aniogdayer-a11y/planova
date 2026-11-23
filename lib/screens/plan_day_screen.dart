import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../providers/planner_provider.dart';
import '../services/scheduler_service.dart';
import '../widgets/planner_actions.dart';
import '../theme/app_colors.dart';

class PlanDayScreen extends StatefulWidget {
  const PlanDayScreen({super.key});
  @override
  State<PlanDayScreen> createState() => _PlanDayScreenState();
}

class _PlanDayScreenState extends State<PlanDayScreen> {
  final _taskController = TextEditingController();

  @override
  void dispose() {
    _taskController.dispose();
    super.dispose();
  }

  bool _addTask(PlannerProvider planner) {
    if (!planner.addDraftTask(_taskController.text)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Enter a unique task name, up to 200 characters. You can add up to 30 tasks.',
          ),
        ),
      );
      return false;
    }
    _taskController.clear();
    return true;
  }

  Future<void> _pickTime(PlannerProvider planner) async {
    final current = SchedulerService.parseTimeString(planner.draftStartTime);
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(alwaysUse24HourFormat: planner.is24Hour),
        child: child!,
      ),
    );
    if (picked != null) {
      planner.setDraftStartTime(
        SchedulerService.formatTime(
          DateTime(2000, 1, 1, picked.hour, picked.minute),
        ),
      );
    }
  }

  Future<void> _generate(PlannerProvider planner) async {
    if (_taskController.text.trim().isNotEmpty && !_addTask(planner)) return;
    FocusScope.of(context).unfocus();
    if (await plannerAction(context, planner.generateAndSaveDraft) && mounted) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final planner = context.watch<PlannerProvider>();
    final busy = planner.isGenerating || planner.isSaving;
    return PopScope(
      canPop: !busy,
      child: Scaffold(
        appBar: AppBar(title: const Text('Plan your day')),
        bottomNavigationBar: Container(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            border: Border(top: BorderSide(color: AppColors.border)),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Center(
                heightFactor: 1,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 860),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed:
                          busy ||
                              (planner.draftTasks.isEmpty &&
                                  _taskController.text.trim().isEmpty)
                          ? null
                          : () => _generate(planner),
                      child: Text(
                        planner.isSaving
                            ? 'Saving...'
                            : planner.isGenerating
                            ? 'Generating...'
                            : 'Generate plan',
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        body: SafeArea(
          child: AbsorbPointer(
            absorbing: busy,
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 900),
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Text(DateFormat('EEEE, MMMM d').format(planner.draftDate)),
                    const SizedBox(height: 24),
                    Text(
                      'Tasks',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _taskController,
                            maxLength: 200,
                            textCapitalization: TextCapitalization.sentences,
                            onSubmitted: (_) => _addTask(planner),
                            onChanged: (_) => setState(() {}),
                            decoration: const InputDecoration(
                              hintText: 'e.g. Review notes',
                              counterText: '',
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filled(
                          tooltip: 'Add task',
                          onPressed: () => _addTask(planner),
                          icon: const Icon(Icons.add),
                          style: IconButton.styleFrom(
                            minimumSize: const Size(50, 50),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (planner.draftTasks.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text('Add your first task above.'),
                      ),
                    ...List.generate(planner.draftTasks.length, (index) {
                      final task = planner.draftTasks[index];
                      final durations = {
                        0,
                        15,
                        30,
                        45,
                        60,
                        90,
                        120,
                        task.durationMinutes,
                      }.toList()..sort();
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(14, 8, 4, 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      task.title,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Remove ${task.title}',
                                    onPressed: () =>
                                        planner.removeDraftTask(index),
                                    icon: const Icon(Icons.close, size: 18),
                                  ),
                                ],
                              ),
                              DropdownButton<int>(
                                value: task.durationMinutes,
                                isExpanded: true,
                                underline: const SizedBox.shrink(),
                                items: durations
                                    .map(
                                      (duration) => DropdownMenuItem(
                                        value: duration,
                                        child: Text(
                                          duration == 0
                                              ? 'Auto estimate'
                                              : '$duration minutes',
                                          style: const TextStyle(fontSize: 13),
                                        ),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (value) {
                                  if (value != null &&
                                      value != task.durationMinutes) {
                                    planner.setDraftDuration(index, value);
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                    const SizedBox(height: 20),
                    Card(
                      child: ListTile(
                        title: const Text('Start time'),
                        trailing: const Icon(Icons.schedule, size: 20),
                        subtitle: Text(
                          planner.displayTime(planner.draftStartTime),
                        ),
                        onTap: () => _pickTime(planner),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Card(
                      child: Column(
                        children: [
                          SwitchListTile(
                            title: const Text('Include breaks'),
                            value: planner.draftHasBreaks,
                            onChanged: planner.setDraftHasBreaks,
                          ),
                          if (planner.draftHasBreaks)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: DropdownButton<int>(
                                      isExpanded: true,
                                      value: planner.draftBreakCount,
                                      items: [1, 2, 3]
                                          .map(
                                            (n) => DropdownMenuItem(
                                              value: n,
                                              child: Text(
                                                '$n break${n == 1 ? '' : 's'}',
                                              ),
                                            ),
                                          )
                                          .toList(),
                                      onChanged: (n) {
                                        if (n != null) {
                                          planner.setDraftBreakCount(n);
                                        }
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: DropdownButton<int>(
                                      isExpanded: true,
                                      value: planner.draftBreakDuration,
                                      items:
                                          ({
                                                5,
                                                10,
                                                15,
                                                planner.draftBreakDuration,
                                              }.toList()..sort())
                                              .map(
                                                (n) => DropdownMenuItem(
                                                  value: n,
                                                  child: Text('$n min'),
                                                ),
                                              )
                                              .toList(),
                                      onChanged: (n) {
                                        if (n != null) {
                                          planner.setDraftBreakDuration(n);
                                        }
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    if (planner.isGenerating)
                      const Padding(
                        padding: EdgeInsets.only(top: 16),
                        child: LinearProgressIndicator(),
                      ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
