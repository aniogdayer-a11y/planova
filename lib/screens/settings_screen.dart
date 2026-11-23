import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/planner_provider.dart';
import '../providers/auth_provider.dart';
import '../widgets/page_layout.dart';
import '../widgets/planner_actions.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final planner = context.watch<PlannerProvider>();
    final auth = context.watch<AuthProvider?>();
    return PageLayout(
      title: 'Settings',
      maxWidth: 900,
      children: [
        Card(
          child: SwitchListTile(
            title: const Text('24-hour time'),
            subtitle: Text(planner.is24Hour ? '14:00' : '2:00 PM'),
            value: planner.is24Hour,
            onChanged: (value) =>
                plannerAction(context, () => planner.toggleTimeFormat(value)),
          ),
        ),
        if (auth?.user != null) ...[
          const SizedBox(height: 32),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    auth!.user!.email,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  const Text('Synced across your devices.'),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: auth.busy
                        ? null
                        : () => plannerAction(context, auth.logout),
                    icon: const Icon(Icons.logout, size: 18),
                    label: const Text('Sign out'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}
