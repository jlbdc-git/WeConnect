import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/profile.dart';
import '../repositories/auth_repository.dart';
import '../repositories/friend_repository.dart';
import '../repositories/message_repository.dart';
import '../repositories/profile_repository.dart';
import '../repositories/server_repository.dart';
import '../repositories/settings_repository.dart';
import '../services/voice_service.dart';

// ---------------------------------------------------------------------------
// Infrastructure singletons. Overridden in main() after Supabase.initialize
// and in tests with fakes (dependency injection without a DI framework).
// ---------------------------------------------------------------------------

final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('override in main()');
});

final edgeFunctionUrlProvider = Provider<String>((ref) {
  throw UnimplementedError('override in main()');
});

// ---------------------------------------------------------------------------
// Repositories
// ---------------------------------------------------------------------------

final authRepositoryProvider = Provider<AuthRepository>(
    (ref) => AuthRepository(ref.watch(supabaseClientProvider)));

final profileRepositoryProvider = Provider<ProfileRepository>(
    (ref) => ProfileRepository(ref.watch(supabaseClientProvider)));

final friendRepositoryProvider = Provider<FriendRepository>(
    (ref) => FriendRepository(ref.watch(supabaseClientProvider)));

final serverRepositoryProvider = Provider<ServerRepository>(
    (ref) => ServerRepository(ref.watch(supabaseClientProvider)));

final messageRepositoryProvider = Provider<MessageRepository>(
    (ref) => MessageRepository(ref.watch(supabaseClientProvider)));

final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  return SettingsRepository(
    ref.watch(supabaseClientProvider),
    ref.watch(sharedPreferencesProvider),
  );
});

// ---------------------------------------------------------------------------
// Voice service (one instance for the whole app — owns the LiveKit room)
// ---------------------------------------------------------------------------

final voiceServiceProvider = Provider<VoiceService>((ref) {
  final service = VoiceService(
    supabase: ref.watch(supabaseClientProvider),
    edgeFunctionBase: ref.watch(edgeFunctionUrlProvider),
  );
  ref.onDispose(service.dispose);
  return service;
});

// ---------------------------------------------------------------------------
// Auth state
// ---------------------------------------------------------------------------

/// Distinct app-level auth states (drives the router).
enum AuthStatus { loading, authenticated, unauthenticated }

final authStateProvider = StreamProvider<AuthStatus>((ref) {
  final repo = ref.watch(authRepositoryProvider);
  return repo.authState.map((event) {
    // AuthChangeEvent.signedOut / tokenRemoved → unauthenticated.
    // signedIn, initialSession with a session → authenticated.
    final hasSession = repo.currentSession != null;
    switch (event.event) {
      case AuthChangeEvent.signedOut:
        return AuthStatus.unauthenticated;
      case AuthChangeEvent.initialSession:
        return hasSession
            ? AuthStatus.authenticated
            : AuthStatus.unauthenticated;
      default:
        return hasSession ? AuthStatus.authenticated : AuthStatus.unauthenticated;
    }
  });
});

/// Current user's profile.
final myProfileProvider = FutureProvider<Profile?>((ref) async {
  final client = ref.watch(supabaseClientProvider);
  final uid = client.auth.currentUser?.id;
  if (uid == null) return null;
  try {
    final data =
        await client.from('profiles').select().eq('id', uid).maybeSingle();
    if (data == null) return null;
    return Profile.fromJson(data);
  } catch (_) {
    return null;
  }
});
