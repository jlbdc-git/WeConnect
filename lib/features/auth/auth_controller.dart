import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../core/state/providers.dart';
import '../friends/friends_controller.dart';
import '../servers/servers_controller.dart';
import '../voice/voice_controller.dart';

/// Async state for the auth screens (login/registration).
class AuthController extends AutoDisposeAsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<void> signIn(String email, String password) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await ref.read(authRepositoryProvider).signIn(
            email: email.trim(),
            password: password,
          );
    });
  }

  Future<void> signUp(
      String email, String password, String username, String displayName) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await ref.read(authRepositoryProvider).signUp(
            email: email.trim(),
            password: password,
            username: username.trim().toLowerCase(),
            displayName: displayName.trim(),
          );
    });
  }

  /// Signs out and returns to the login screen only after the session is
  /// actually gone (never a bare navigation that leaves the session alive).
  Future<void> signOut() async {
    // 1. Terminate voice/PTT first: no dangling LiveKit room or global PTT
    //    hook outliving the session.
    try {
      await ref.read(voiceControllerProvider.notifier).leave();
    } catch (_) {
      // Best-effort — logout must proceed even if voice cleanup throws.
    }

    // 2. Sign out (server revoke + local session removal).
    await ref.read(authRepositoryProvider).signOut();

    // 3. Drop stale in-memory caches so a login by a different user can't
    //    see the previous account's data; the authStateProvider stream
    //    emission rebuilds the router, which lands on /login.
    ref.invalidate(myProfileProvider);
    ref.invalidate(serversControllerProvider);
    ref.invalidate(friendsControllerProvider);
  }
}

final authControllerProvider = AutoDisposeAsyncNotifierProvider<AuthController,
    void>(AuthController.new);

/// Extracts the user-facing message from any error.
String authErrorMessage(Object error) {
  if (error is AppException) return error.message ?? error.code;
  return 'Something went wrong. Please try again.';
}
