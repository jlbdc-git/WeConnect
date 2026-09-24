import 'package:supabase_flutter/supabase_flutter.dart';

/// App-level auth states (drives the router).
enum AuthStatus { loading, authenticated, unauthenticated }

/// Maps a Supabase auth event (+ whether a local session exists) to the
/// app-level auth status. Pure function — unit-testable without a backend.
///
/// Contract relied on by the router:
///   • signedOut        → ALWAYS unauthenticated (regardless of any stale
///     session object — gotrue may not have detached it yet when the event
///     fires). This is what guarantees logout redirects to /login.
///   • initialSession   → authenticated iff a session exists (restores a
///     persisted login at startup, unauthenticated on first launch).
///   • signedIn/other   → authenticated iff a session exists.
AuthStatus authStatusFromEvent(AuthChangeEvent event, bool hasSession) {
  switch (event) {
    case AuthChangeEvent.signedOut:
      return AuthStatus.unauthenticated;
    case AuthChangeEvent.initialSession:
    case AuthChangeEvent.signedIn:
    case AuthChangeEvent.tokenRefreshed:
    case AuthChangeEvent.userUpdated:
    case AuthChangeEvent.mfaChallengeVerified:
    case AuthChangeEvent.passwordRecovery:
      return hasSession ? AuthStatus.authenticated : AuthStatus.unauthenticated;
    // Deprecated placeholder value in gotrue (never emitted at runtime).
    // ignore: deprecated_member_use
    case AuthChangeEvent.userDeleted:
      return hasSession ? AuthStatus.authenticated : AuthStatus.unauthenticated;
  }
}
