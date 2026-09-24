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

  /// Signs the user out of THIS session (SignOutScope.local) and revokes
  /// the refresh token server-side.
  ///
  /// gotrue clears the local session and emits `signedOut` BEFORE calling
  /// the revoke endpoint; if that call fails (offline, transient 5xx), it
  /// rethrows even though the user is already signed out locally. We
  /// swallow such failures so the UI always completes the sign-out, and we
  /// double-check `currentSession` — re-removing it if the SDK kept any
  /// stale session object alive — so the router can never see an
  /// authenticated state after logout.
  Future<void> signOut() async {
    // Default scope is SignOutScope.local: only this session is revoked.
    try {
      await _client.auth.signOut();
    } catch (_) {
      // Server-side revoke failed (offline / transient). The local session
      // is already cleared by the SDK in this case; make sure it stays so.
    } finally {
      if (_client.auth.currentSession != null) {
        try {
          await _client.auth.signOut();
        } catch (_) {
          // Last-resort retry failed too; the router treats "no session"
          // as unauthenticated, and gotrue has already emitted signedOut.
        }
      }
    }
  }

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
