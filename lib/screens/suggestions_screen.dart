import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/planner_provider.dart';
import '../widgets/page_layout.dart';
import 'plan_day_screen.dart';

class SuggestionsScreen extends StatelessWidget {
  const SuggestionsScreen({super.key});
  @override
  Widget build(BuildContext context) => PageLayout(
    title: 'Planning tips',
    children: [
      const Card(
        child: Column(
          children: [
            ListTile(
              leading: Icon(Icons.checklist),
              title: Text('Keep the list short'),
              subtitle: Text(
                'Start with the tasks you can realistically finish today.',
              ),
            ),
            Divider(height: 1),
            ListTile(
              leading: Icon(Icons.schedule),
              title: Text('Give tasks enough time'),
              subtitle: Text('Set a duration or use Auto estimate.'),
            ),
            Divider(height: 1),
            ListTile(
              leading: Icon(Icons.coffee_outlined),
              title: Text('Include a break'),
              subtitle: Text(
                'A short pause between focus sessions helps keep your day manageable.',
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 24),
      ElevatedButton(
        onPressed: () {
          context.read<PlannerProvider>().preparePlanDraft();
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
