import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config/app_config.dart';
import 'theme/app_theme.dart';
import 'providers/planner_provider.dart';
import 'providers/auth_provider.dart';
import 'services/remote_planner_repository.dart';
import 'screens/auth_screen.dart';
import 'screens/main_scaffold.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (AppConfig.usesSupabase) {
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      publishableKey: AppConfig.supabaseKey,
    );
  }
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.white,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );
  runApp(const AutoTaskSchedulerApp());
}

class AutoTaskSchedulerApp extends StatelessWidget {
  final PlannerProvider? plannerProvider;
  final AuthProvider? authProvider;
  const AutoTaskSchedulerApp({
    super.key,
    this.plannerProvider,
    this.authProvider,
  });
  @override
  Widget build(BuildContext context) {
    // Explicit repository injection keeps existing isolated widget tests independent of network sign-in.
    if (plannerProvider != null) {
      return ChangeNotifierProvider.value(
        value: plannerProvider!,
        child: Consumer<PlannerProvider>(
          builder: (context, planner, _) => MaterialApp(
            title: 'Planova',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.forPalette(planner.colorTheme),
            home: const MainScaffold(),
          ),
        ),
      );
    }
    return ChangeNotifierProvider<AuthProvider>(
      create: (_) => authProvider ?? AuthProvider(),
      child: Consumer<AuthProvider>(
        builder: (context, auth, _) {
          final app = MaterialApp(
            key: ValueKey(auth.user?.id ?? 'signed-out'),
            title: 'Planova',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            home: auth.initializing
                ? const Scaffold(
                    body: Center(child: CircularProgressIndicator()),
                  )
                : auth.user == null
                ? const AuthScreen()
                : const MainScaffold(),
          );
          if (auth.user == null) return app;
          // Keep the account repository above the Navigator so every route
          // shares it, and dispose all routes and data when the account changes.
          return ChangeNotifierProvider(
            key: ValueKey(auth.user!.id),
            create: (_) => PlannerProvider(
              repository: RemotePlannerRepository(client: auth.api),
            ),
            child: Consumer<PlannerProvider>(
              builder: (context, planner, _) => MaterialApp(
                title: 'Planova',
                debugShowCheckedModeBanner: false,
                theme: AppTheme.forPalette(planner.colorTheme),
                home: const MainScaffold(),
              ),
            ),
          );
        },
      ),
    );
  }
}
