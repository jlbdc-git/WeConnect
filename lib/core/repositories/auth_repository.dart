import 'package:supabase_flutter/supabase_flutter.dart';

import '../errors/app_exception.dart';

/// Wraps Supabase Auth. All auth calls funnel through here so the UI
/// never touches Supabase directly.
class AuthRepository {
  AuthRepository(this._client);

  final SupabaseClient _client;

  /// Emits the current user on every auth state change (including restore
  /// from persisted session at app start).
  Stream<AuthState> get authState => _client.auth.onAuthStateChange;

  Session? get currentSession => _client.auth.currentSession;
  User? get currentUser => _client.auth.currentUser;

  Future<void> signUp({
    required String email,
    required String password,
    required String username,
    String? displayName,
  }) async {
    try {
      final res = await _client.auth.signUp(
        email: email,
        password: password,
        data: {
          'username': username,
          'display_name': displayName ?? username,
        },
      );
      // Email-confirmation off: session should be present.
      if (res.session == null) {
        throw const AppException(
          'auth_confirm_email',
          message:
              'Check your email to confirm your account before signing in.',
        );
      }
    } on AuthException catch (e) {
      throw AppException(
        'auth_failed',
        message: _mapAuthError(e),
        cause: e,
      );
    } catch (e) {
      throw AppErrors.from(e, context: 'Sign-up failed');
    }
  }

  Future<void> signIn({
    required String email,
    required String password,
  }) async {
    try {
      await _client.auth.signInWithPassword(email: email, password: password);
    } on AuthException catch (e) {
      throw AppException('auth_failed', message: _mapAuthError(e), cause: e);
    } catch (e) {
      throw AppErrors.from(e, context: 'Sign-in failed');
    }
  }

  Future<void> signOut() => _client.auth.signOut();

  static String _mapAuthError(AuthException e) {
    final m = e.message.toLowerCase();
    if (m.contains('invalid login') || m.contains('signin')) {
      return 'Incorrect email or password.';
    }
    if (m.contains('already registered')) {
      return 'That email is already registered.';
    }
    if (m.contains('password')) {
      return 'Password must be at least 6 characters.';
    }
    if (m.contains('rate limit')) {
      return 'Too many attempts. Try again in a moment.';
    }
    return e.message;
  }
}
