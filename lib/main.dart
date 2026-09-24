import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/config/app_config.dart';
import 'core/navigation/app_router.dart';
import 'core/state/providers.dart';
import 'core/theme/app_theme.dart';
import 'core/utils/app_log.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Load config (dart-define first, secure storage fallback).
  await AppConfig.load();

  // 2. Local settings storage.
  final prefs = await SharedPreferences.getInstance();

  // 3. Supabase (only if configured — otherwise the setup screen shows).
  if (AppConfig.isConfigured) {
    await Supabase.initialize(
      url: AppConfig.supabaseUrl!,
      // Client-safe publishable (anon) key — RLS is the enforcement layer.
      publishableKey: AppConfig.supabaseAnonKey!,
      // Auth session persists via encrypted storage on Android and
      // DPAPI-backed storage on Windows — no manual token handling.
    );
  }

  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      edgeFunctionUrlProvider.overrideWithValue(
        '${AppConfig.supabaseUrl ?? ''}/functions/v1',
      ),
    ],
  );

  runApp(UncontrolledProviderScope(
    container: container,
    child: const WeConnectApp(),
  ));
}

class WeConnectApp extends ConsumerWidget {
  const WeConnectApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    return MaterialApp.router(
      title: 'WeConnect',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      routerConfig: router,
    );
  }
}

// Keep the logger referenced so tree shaking does not complain in dev builds.
// ignore: unused_element
void _logBootstrap() => AppLog.d('bootstrap complete');
