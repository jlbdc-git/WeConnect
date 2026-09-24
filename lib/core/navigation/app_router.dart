import 'package:flutter/foundation.dart' show ChangeNotifier;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/login_screen.dart';
import '../../features/auth/register_screen.dart';
import '../../features/home/home_shell.dart';
import '../../features/settings/setup_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../state/providers.dart';
import '../state/auth_status_mapper.dart' show AuthStatus;

/// Bridges Riverpod into GoRouter's `refreshListenable`: notifies the router
/// on every [authStateProvider] emission so the redirect re-runs even though
/// the GoRouter instance itself is cached. This is what makes logout land on
/// /login reliably — without it, a cached router never re-evaluates the
/// redirect and the UI can stay on an authenticated screen.
class _RouterRefresh extends ChangeNotifier {
  _RouterRefresh(Ref ref) {
    ref.listen<AsyncValue<AuthStatus>>(authStateProvider, (prev, next) {
      notifyListeners();
    });
  }
}

final appRouterProvider = Provider<GoRouter>((ref) {
  final refresh = _RouterRefresh(ref);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: refresh,
    redirect: (context, state) {
      // Always read the CURRENT auth status — never a value captured when
      // the provider first built.
      final status =
          ref.read(authStateProvider).valueOrNull ?? AuthStatus.loading;
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
