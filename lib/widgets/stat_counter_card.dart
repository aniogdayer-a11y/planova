import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class StatCounterCard extends StatelessWidget {
  final int tasksDone;
  final int pendingTasks;
  final int streakDays;

  const StatCounterCard({
    super.key,
    required this.tasksDone,
    required this.pendingTasks,
    required this.streakDays,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _buildItem('$tasksDone', 'Tasks done')),
        const SizedBox(width: 10),
        Expanded(child: _buildItem('$pendingTasks', 'Pending tasks')),
        const SizedBox(width: 10),
        Expanded(child: _buildItem('$streakDays days', 'Streak')),
      ],
    );
  }

  Widget _buildItem(String value, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: AppColors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
