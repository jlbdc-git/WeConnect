import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/login_screen.dart';
import '../../features/auth/register_screen.dart';
import '../../features/home/home_shell.dart';
import '../../features/settings/setup_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../state/providers.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final authStatus = ref.watch(authStateProvider);

  return GoRouter(
    initialLocation: '/',
    redirect: (context, state) {
      final status = authStatus.valueOrNull ?? AuthStatus.loading;
      final loggedIn = status == AuthStatus.authenticated;
      final onAuthScreen = state.matchedLocation == '/login' ||
          state.matchedLocation == '/register';
      final onSetup = state.matchedLocation == '/setup';

      // Still restoring the session: stay put.
      if (status == AuthStatus.loading && state.matchedLocation == '/') {
        return '/login';
      }

      if (!loggedIn && !onAuthScreen && !onSetup) return '/login';
      if (loggedIn && (onAuthScreen || onSetup)) return '/';
      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/register',
        builder: (context, state) => const RegisterScreen(),
      ),
      GoRoute(
        path: '/setup',
        builder: (context, state) => const SetupScreen(),
      ),
      GoRoute(
        path: '/',
        builder: (context, state) => const HomeShell(),
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsScreen(),
      ),
    ],
  );
});
