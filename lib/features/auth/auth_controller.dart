import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../core/state/providers.dart';

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

  Future<void> signOut() async {
    await ref.read(authRepositoryProvider).signOut();
  }
}

final authControllerProvider = AutoDisposeAsyncNotifierProvider<AuthController,
    void>(AuthController.new);

/// Extracts the user-facing message from any error.
String authErrorMessage(Object error) {
  if (error is AppException) return error.message ?? error.code;
  return 'Something went wrong. Please try again.';
}
