import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/planner_provider.dart';
import '../widgets/page_layout.dart';
import '../widgets/planner_actions.dart';
import 'plan_day_screen.dart';

class SuggestionsScreen extends StatelessWidget {
  const SuggestionsScreen({super.key});
  static const suggestions = [
    (
      id: 'short_list',
      icon: Icons.checklist,
      title: 'Keep the list short',
      text: 'Start with the tasks you can realistically finish today.',
    ),
    (
      id: 'enough_time',
      icon: Icons.schedule,
      title: 'Give yourself time',
      text: 'Leave a little room between tasks so you do not have to rush.',
    ),
    (
      id: 'break',
      icon: Icons.coffee_outlined,
      title: 'Take a breather',
      text: 'Add a short break between focus sessions.',
    ),
  ];
  @override
  Widget build(BuildContext context) {
    final planner = context.watch<PlannerProvider>();
    return PageLayout(
      title: 'Suggestions',
      maxWidth: 900,
      children: [
        for (final suggestion in suggestions) ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(suggestion.icon),
                  const SizedBox(height: 12),
                  Text(
                    suggestion.title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 6),
                  Text(suggestion.text),
                  const SizedBox(height: 12),
                  Semantics(
                    toggled: planner.likesSuggestion(suggestion.id),
                    child: TextButton.icon(
                      key: ValueKey('like-${suggestion.id}'),
                      onPressed:
                          planner.preferenceSaving(
                            'suggestion_like_${suggestion.id}',
                          )
                          ? null
                          : () => plannerAction(
                              context,
                              () => planner.toggleSuggestion(suggestion.id),
                            ),
                      icon: Icon(
                        planner.likesSuggestion(suggestion.id)
                            ? Icons.favorite
                            : Icons.favorite_border,
                      ),
                      label: Text(
                        planner.likesSuggestion(suggestion.id)
                            ? 'Liked'
                            : 'Like',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        const SizedBox(height: 12),
        ElevatedButton(
          onPressed: () {
            planner.preparePlanDraft();
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PlanDayScreen()),
            );
          },
          child: const Text('Plan your day'),
        ),
      ],
    );
  }
}
