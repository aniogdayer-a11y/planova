import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import '../providers/planner_provider.dart';
import '../theme/app_colors.dart';
import '../widgets/page_layout.dart';
import '../widgets/planner_actions.dart';
import '../widgets/account_avatar.dart';
import '../widgets/avatar_editor.dart';
import '../providers/auth_provider.dart';
import 'auth_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _avatarBusy = false;
  Future<void> _customizeAvatar(PlannerProvider planner) async {
    final bytes = await showDialog<List<int>>(
      context: context,
      builder: (_) => AvatarEditor(name: planner.profile?.name ?? 'P'),
    );
    if (bytes == null || !mounted) return;
    setState(() => _avatarBusy = true);
    try {
      await plannerAction(context, () => planner.updateAvatar(bytes));
    } finally {
      if (mounted) setState(() => _avatarBusy = false);
    }
  }

  Future<void> _chooseAvatar(
    PlannerProvider planner, {
    bool remove = false,
  }) async {
    if (_avatarBusy) return;
    setState(() => _avatarBusy = true);
    try {
      if (remove) {
        await plannerAction(context, () => planner.updateAvatar(null));
        return;
      }
      final photo = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 80,
        requestFullMetadata: false,
      );
      if (photo == null || !mounted) return;
      await plannerAction(context, () async {
        if (await photo.length() > 2 * 1024 * 1024) {
          throw const FormatException('Choose a photo smaller than 2 MB.');
        }
        await planner.updateAvatar(await photo.readAsBytes());
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not open your photos. Please try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _avatarBusy = false);
    }
  }

  Future<void> _editName(BuildContext context, PlannerProvider planner) async {
    final controller = TextEditingController(text: planner.profile?.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Your name'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 40,
          textCapitalization: TextCapitalization.words,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                Navigator.pop(context, controller.text.trim());
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    // Let the dialog route finish using its text field before disposing.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    controller.dispose();
    if (name != null && context.mounted) {
      await plannerAction(context, () => planner.updateName(name));
    }
  }

  @override
  Widget build(BuildContext context) {
    final planner = context.watch<PlannerProvider>();
    final auth = context.watch<AuthProvider?>();
    final weekly = planner.weeklyActivity;
    return PageLayout(
      title: 'Profile',
      children: [
        Card(
          child: Column(
            children: [
              ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                leading: AccountAvatar(
                  name: planner.profile?.name ?? 'Planova',
                  photo: planner.profile?.avatarUrl ?? '',
                ),
                title: Text(planner.profile?.name ?? 'Dayer'),
                subtitle: Text(auth?.user?.email ?? 'Personal planner'),
                trailing: IconButton(
                  tooltip: 'Edit name',
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  onPressed: () => _editName(context, planner),
                ),
              ),
              if (planner.canUpdateAvatar)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(
                      spacing: 12,
                      runSpacing: 4,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _avatarBusy
                              ? null
                              : () => _customizeAvatar(planner),
                          icon: const Icon(Icons.face_outlined, size: 20),
                          label: const Text('Customize avatar'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _avatarBusy
                              ? null
                              : () => _chooseAvatar(planner),
                          icon: const Icon(
                            Icons.add_photo_alternate_outlined,
                            size: 20,
                          ),
                          label: Text(
                            _avatarBusy ? 'Saving photo...' : 'Change photo',
                          ),
                        ),
                        if (planner.profile?.avatarUrl.isNotEmpty ?? false)
                          TextButton(
                            onPressed: _avatarBusy
                                ? null
                                : () => _chooseAvatar(planner, remove: true),
                            child: const Text('Remove photo'),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        if (auth?.user != null) ...[
          Card(
            child: ListTile(
              leading: const Icon(Icons.lock_outline),
              title: const Text('Account security'),
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AuthScreen(
                    startWithReset: true,
                    initialEmail: auth!.user!.email,
                  ),
                ),
              ),
              child: const Text('Reset password'),
            ),
          ),
          const SizedBox(height: 16),
        ],
        Text('Last 7 days', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 8),
            child: Row(
              children: weekly.map((activity) {
                final date = DateTime.parse(activity['date'] as String);
                final count = activity['tasks_completed'] as int;
                return Expanded(
                  child: Semantics(
                    label:
                        '${DateFormat('EEEE, MMMM d').format(date)}, $count completed tasks',
                    child: Column(
                      children: [
                        Text(
                          DateFormat('EEEEE').format(date),
                          style: const TextStyle(fontSize: 12),
                        ),
                        const SizedBox(height: 10),
                        CircleAvatar(
                          radius: 16,
                          backgroundColor: count > 0
                              ? AppColors.primary
                              : AppColors.surfaceSubtle,
                          child: Text(
                            '${date.day}',
                            style: TextStyle(
                              fontSize: 12,
                              color: count > 0
                                  ? Colors.white
                                  : AppColors.textSecondary,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text('$count', style: const TextStyle(fontSize: 12)),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
        const SizedBox(height: 8),
        const SizedBox(height: 24),
        Card(
          child: ListTile(
            leading: const Icon(Icons.local_fire_department_outlined),
            title: Text('${planner.streakCount}-day streak'),
            subtitle: const Text(
              'Complete at least one task each day to keep it going.',
            ),
          ),
        ),
      ],
    );
  }
}
