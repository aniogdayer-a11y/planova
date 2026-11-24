import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/planner_provider.dart';
import '../theme/app_colors.dart';
import '../widgets/page_layout.dart';
import '../widgets/planner_actions.dart';

class SuggestionsScreen extends StatelessWidget {
  const SuggestionsScreen({super.key});
  static const suggestions = [
    (
      id: 'short_list',
      text: 'Start with the tasks you can realistically finish today.',
    ),
    (
      id: 'enough_time',
      text: 'Leave a little room between tasks so you do not have to rush.',
    ),
    (id: 'break', text: 'Add a short break between focus sessions.'),
  ];

  @override
  Widget build(BuildContext context) {
    final planner = context.watch<PlannerProvider>();
    return PageLayout(
      title: 'Suggestions',
      maxWidth: 760,
      children: [
        for (var index = 0; index < suggestions.length; index++) ...[
          if (index > 0) const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor:
                      Theme.of(context).colorScheme.primaryContainer,
                  child: const Icon(
                    Icons.chat_bubble_outline_rounded,
                    size: 16,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'Planova',
                            style: Theme.of(context)
                                .textTheme
                                .labelLarge
                                ?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textPrimary,
                                ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '• Tip',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                  color: AppColors.textTertiary,
                                ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        suggestions[index].text,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: AppColors.textPrimary,
                            ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Semantics(
                  toggled: planner.likesSuggestion(suggestions[index].id),
                  child: IconButton(
                    key: ValueKey('like-${suggestions[index].id}'),
                    tooltip: planner.likesSuggestion(suggestions[index].id)
                        ? 'Unlike'
                        : 'Like',
                    onPressed:
                        planner.preferenceSaving(
                          'suggestion_like_${suggestions[index].id}',
                        )
                        ? null
                        : () => plannerAction(
                            context,
                            () =>
                                planner.toggleSuggestion(suggestions[index].id),
                          ),
                    icon: Icon(
                      planner.likesSuggestion(suggestions[index].id)
                          ? Icons.favorite
                          : Icons.favorite_border,
                      size: 20,
                      color: planner.likesSuggestion(suggestions[index].id)
                          ? const Color(0xFFE05353)
                          : AppColors.textTertiary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

