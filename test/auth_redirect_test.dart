import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:we_connect/core/state/auth_status_mapper.dart';

/// Pins the auth-event → router-status contract:
///
///   • signedOut ALWAYS yields unauthenticated — even if a stale session
///     object is still attached. This is the guarantee that a real Supabase
///     sign-out (which emits `signedOut`) sends the user to /login and
///     locks them out of authenticated routes.
///   • initialSession restores persisted logins (authenticated) and yields
///     unauthenticated on first launch — so logging back in after logout
///     restores access exactly once.
void main() {
  group('authStatusFromEvent — logout contract', () {
    test('signedOut is unauthenticated even with a stale session', () {
      // gotrue emits signedOut BEFORE fully detaching the session object in
      // some paths; the mapper must not trust the stale session.
      expect(
        authStatusFromEvent(AuthChangeEvent.signedOut, true),
        AuthStatus.unauthenticated,
      );
      expect(
        authStatusFromEvent(AuthChangeEvent.signedOut, false),
        AuthStatus.unauthenticated,
      );
    });

    test('a session-refresh event without a session is unauthenticated', () {
      expect(
        authStatusFromEvent(AuthChangeEvent.tokenRefreshed, false),
        AuthStatus.unauthenticated,
      );
      expect(
        authStatusFromEvent(AuthChangeEvent.userUpdated, false),
        AuthStatus.unauthenticated,
      );
    });
  });

  group('authStatusFromEvent — session restore / login-back contract', () {
    test('initialSession with a session is authenticated', () {
      expect(
        authStatusFromEvent(AuthChangeEvent.initialSession, true),
        AuthStatus.authenticated,
      );
    });

    test('initialSession without a session is unauthenticated', () {
      expect(
        authStatusFromEvent(AuthChangeEvent.initialSession, false),
        AuthStatus.unauthenticated,
      );
    });

    test('signedIn with a session is authenticated (login after logout)', () {
      expect(
        authStatusFromEvent(AuthChangeEvent.signedIn, true),
        AuthStatus.authenticated,
      );
    });

    test('signedIn without a session is unauthenticated', () {
      expect(
        authStatusFromEvent(AuthChangeEvent.signedIn, false),
        AuthStatus.unauthenticated,
      );
    });
  });
}
