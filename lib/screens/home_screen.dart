import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/app_config.dart';
import '../providers/planner_provider.dart';
import '../widgets/calendar_widget.dart';
import '../widgets/page_layout.dart';
import '../widgets/planner_actions.dart';
import '../widgets/timeline_slot_card.dart';
import '../theme/app_colors.dart';
import 'plan_day_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});
  void _plan(BuildContext context, PlannerProvider planner) {
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
    final next = plan?.scheduleSlots
        .where((s) => !s.isCompleted && s.taskId != null)
        .firstOrNull;
    final calendar = CalendarWidget(
      selectedDate: planner.selectedDate,
      onDateSelected: (date) =>
          plannerAction(context, () => planner.selectDate(date)),
    );
    final planButton = ElevatedButton.icon(
      onPressed: planner.isLoadingPlan ? null : () => _plan(context, planner),
      icon: const Icon(Icons.add, size: 18),
      label: Text(plan == null ? 'Plan this day' : 'Edit this day'),
    );
    final downloadBanner = AppConfig.apkDownloadUri == null
        ? null
        : _ApkDownloadBanner(uri: AppConfig.apkDownloadUri!);
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;
        return PageLayout(
          title: wide ? 'Overview' : 'Hi, ${planner.profile?.name ?? 'Dayer'}.',
          subtitle: DateFormat('EEEE, MMMM d').format(planner.selectedDate),
          trailing: wide
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton(
                      onPressed: () => plannerAction(
                        context,
                        () => planner.selectDate(DateTime.now()),
                      ),
                      child: const Text('Today'),
                    ),
                    const SizedBox(width: 12),
                    planButton,
                  ],
                )
              : TextButton(
                  onPressed: () => plannerAction(
                    context,
                    () => planner.selectDate(DateTime.now()),
                  ),
                  child: const Text('Today'),
                ),
          children: [
            if (wide) ...[
              Row(
                children: [
                  Expanded(
                    child: _Metric(
                      label: 'Tasks planned',
                      value: '${plan?.tasks.length ?? 0}',
                      icon: Icons.checklist,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _Metric(
                      label: 'Completed',
                      value: '${planner.tasksDoneCount}',
                      icon: Icons.task_alt,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _Metric(
                      label: 'Focus time',
                      value: '${plan?.totalFocusMinutes ?? 0} min',
                      icon: Icons.schedule,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 340,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [calendar, const SizedBox(height: 12)],
                    ),
                  ),
                  const SizedBox(width: 28),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Your schedule',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        if (planner.isLoadingPlan)
                          const Center(child: CircularProgressIndicator())
                        else if (plan == null)
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(28),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(
                                    Icons.event_note_outlined,
                                    size: 32,
                                    color: AppColors.primary,
                                  ),
                                  const SizedBox(height: 20),
                                  const Text(
                                    'Nothing planned yet.',
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  const Text(
                                    'Add your tasks and a start time. We will put them into a schedule with room for breaks.',
                                  ),
                                  const SizedBox(height: 24),
                                  OutlinedButton(
                                    onPressed: () => _plan(context, planner),
                                    child: const Text('Create a plan'),
                                  ),
                                ],
                              ),
                            ),
                          )
                        else ...[
                          Text(
                            '${planner.displayTime(plan.startTime)} - ${planner.displayTime(plan.endTime)}',
                          ),
                          const SizedBox(height: 16),
                          ...plan.scheduleSlots.map(
                            (slot) => TimelineSlotCard(
                              slot: slot,
                              startLabel: planner.displayTime(slot.startTime),
                              endLabel: planner.displayTime(slot.endTime),
                              onChanged: (value) => plannerAction(
                                context,
                                () =>
                                    planner.setSlotCompletion(slot.id!, value),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ] else ...[
              calendar,
              const SizedBox(height: 20),
              planButton,
              const SizedBox(height: 28),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Your day',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (planner.isLoadingPlan)
                const Center(child: CircularProgressIndicator())
              else if (plan == null)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Text('No tasks planned.'),
                  ),
                )
              else ...[
                Text(
                  '${planner.tasksDoneCount} of ${plan.tasks.length} tasks done | ${plan.totalFocusMinutes} min focus',
                ),
                const SizedBox(height: 12),
                Card(
                  child: ListTile(
                    onTap: () => planner.setTabIndex(1),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    title: Text(next?.title ?? 'All tasks complete'),
                    subtitle: Text(
                      next == null
                          ? 'All done for this day.'
                          : '${planner.displayTime(next.startTime)} - ${planner.displayTime(next.endTime)}',
                    ),
                    trailing: const Icon(Icons.chevron_right, size: 20),
                  ),
                ),
              ],
            ],
            if (downloadBanner != null) ...[
              const SizedBox(height: 24),
              downloadBanner,
            ],
          ],
        );
      },
    );
  }
}

class _Metric extends StatelessWidget {
  final String label, value;
  final IconData icon;
  const _Metric({required this.label, required this.value, required this.icon});
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(label)),
              Icon(icon, color: AppColors.primary, size: 20),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            value,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    ),
  );
}

class _ApkDownloadBanner extends StatelessWidget {
  final Uri uri;

  const _ApkDownloadBanner({required this.uri});

  Future<void> _open(BuildContext context) async {
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not open the APK download link.'),
          ),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not open the APK download link: $error'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      border: Border.all(color: AppColors.border),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 16,
      runSpacing: 12,
      children: [
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'You can download Planova as an APK.',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 4),
            Text('Install the Android app on your device.'),
          ],
        ),
        ElevatedButton(
          onPressed: () => _open(context),
          child: const Text('Download APK'),
        ),
      ],
    ),
  );
}
