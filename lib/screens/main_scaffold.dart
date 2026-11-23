import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../widgets/planova_navigation.dart';
import '../widgets/planova_brand.dart';
import '../widgets/account_avatar.dart';
import 'package:provider/provider.dart';
import '../providers/planner_provider.dart';
import '../providers/auth_provider.dart';
import '../theme/app_colors.dart';
import '../widgets/planner_actions.dart';
import 'home_screen.dart';
import 'tasks_screen.dart';
import 'suggestions_screen.dart';
import 'profile_screen.dart';
import 'settings_screen.dart';

class MainScaffold extends StatefulWidget {
  const MainScaffold({super.key});
  @override
  State<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends State<MainScaffold>
    with WidgetsBindingObserver {
  static const _screens = [
    HomeScreen(),
    TasksScreen(),
    SuggestionsScreen(),
    ProfileScreen(),
    SettingsScreen(),
  ];
  Timer? _timer;
  bool _refreshing = false;
  String? _syncError;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(const Duration(seconds: 45), (_) => _refresh());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    if (!mounted || _refreshing) return;
    final planner = context.read<PlannerProvider>();
    if (planner.isLoading || planner.isGenerating || planner.isSaving) return;
    _refreshing = true;
    try {
      await planner.refresh();
      if (mounted) setState(() => _syncError = null);
    } catch (_) {
      if (mounted) {
        setState(
          () => _syncError = 'Could not sync. Showing the last loaded plan.',
        );
      }
    } finally {
      _refreshing = false;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final planner = context.watch<PlannerProvider>();
    final auth = context.watch<AuthProvider?>();
    if (planner.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (planner.error != null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(planner.error!),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: planner.init,
                child: const Text('Try again'),
              ),
              if (auth != null)
                TextButton(
                  onPressed: () => plannerAction(context, auth.logout),
                  child: const Text('Sign out'),
                ),
            ],
          ),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 760;
        final webHeader = kIsWeb && constraints.maxWidth >= 900;
        final content = Column(
          children: [
            if (webHeader)
              PlanovaWebHeader(
                selectedIndex: planner.currentTabIndex,
                onSelected: planner.setTabIndex,
                name: planner.profile?.name ?? 'My account',
                photo: planner.profile?.avatarUrl ?? '',
                onLogout: auth == null || auth.busy
                    ? null
                    : () => plannerAction(context, auth.logout),
              )
            else
              SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 18, 18, 0),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: PlanovaBrand(),
                          ),
                        ),
                      ),
                      AccountAvatar(
                        name: planner.profile?.name ?? 'Planova',
                        photo: planner.profile?.avatarUrl ?? '',
                        size: 32,
                      ),
                    ],
                  ),
                ),
              ),
            if (_syncError != null)
              Container(
                width: double.infinity,
                color: AppColors.surfaceWarm,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Expanded(child: Text(_syncError!)),
                    TextButton(onPressed: _refresh, child: const Text('Retry')),
                  ],
                ),
              ),
            Expanded(
              child: IndexedStack(
                index: planner.currentTabIndex,
                children: _screens,
              ),
            ),
          ],
        );
        return Scaffold(
          body: content,
          bottomNavigationBar: webHeader
              ? null
              : PlanovaNavigation(
                  selectedIndex: planner.currentTabIndex,
                  onSelected: planner.setTabIndex,
                  maxWidth: wide ? 560 : double.infinity,
                ),
        );
      },
    );
  }
}
