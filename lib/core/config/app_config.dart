import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Loads and validates runtime configuration.
///
/// SECURITY: only *public, client-safe* values live here. The Supabase
/// anon key is designed to be public — RLS is the real enforcement layer.
/// Service-role keys, LiveKit API secrets, and TURN credentials are NOT
/// in this file; they live server-side (see supabase/functions/voice-token).
class AppConfig {
  AppConfig._();

  static const _secure = FlutterSecureStorage();

  static String? _supabaseUrl;
  static String? _supabaseAnonKey;

  /// Public, overridable for tests. Loaded from --dart-define at compile
  /// time so secrets never live in the repo.
  static const String supabaseUrlDefault = String.fromEnvironment(
    'SUPABASE_URL',
  );
  static const String supabaseAnonKeyDefault = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
  );
  static const String edgeFunctionUrlDefault = String.fromEnvironment(
    'SUPABASE_EDGE_URL',
  );
  static const String liveKitUrlDefault = String.fromEnvironment('LIVEKIT_URL');

  static String? get supabaseUrl => _supabaseUrl;
  static String? get supabaseAnonKey => _supabaseAnonKey;

  /// LiveKit websocket URL. The voice-token function returns this too,
  /// but we keep a static override for offline dev.
  static String? liveKitUrlOverride;

  /// ICE (STUN/TURN) servers used by LiveKit. Free public STUN by default;
  /// TURN must be provisioned with the LiveKit deployment (coturn), whose
  /// credentials are server-side only.
  static List<Map<String, dynamic>> iceServersOverride = const [];

  static bool _initialized = false;

  /// Loads config: compile-time dart-define first, then persisted secure
  /// storage (settable from the in-app setup screen).
  static Future<void> load() async {
    if (_initialized) return;
    _supabaseUrl = _normalizeUrl(
      supabaseUrlDefault.isNotEmpty
          ? supabaseUrlDefault
          : await _secure.read(key: 'supabase_url'),
    );
    _supabaseAnonKey = supabaseAnonKeyDefault.isNotEmpty
        ? supabaseAnonKeyDefault
        : await _secure.read(key: 'supabase_anon_key');
    _initialized = true;
  }

  static String? _normalizeUrl(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    var url = raw.trim();
    if (!url.startsWith('http')) return null;
    url = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
    return url;
  }

  static bool get isConfigured =>
      _supabaseUrl != null &&
      _supabaseAnonKey != null &&
      _supabaseUrl!.startsWith('http');

  /// Validates the anon key shape — a cheap guard against typos/paste
  /// errors (not a security measure; the key is public by design).
  static bool looksLikeValidAnonKey(String key) =>
      key.length > 40 && key.contains('.');

  static Future<void> saveConfig({
    required String url,
    required String anonKey,
  }) async {
    _supabaseUrl = _normalizeUrl(url);
    _supabaseAnonKey = anonKey.trim();
    await _secure.write(key: 'supabase_url', value: _supabaseUrl!);
    await _secure.write(key: 'supabase_anon_key', value: _supabaseAnonKey!);
    _initialized = true;
  }

  /// Platform-aware LiveKit URL.
  static String? get liveKitUrl {
    if (liveKitUrlDefault.isNotEmpty) return liveKitUrlDefault;
    return liveKitUrlOverride;
  }

  static bool get isAndroid => !kIsWeb && Platform.isAndroid;
  static bool get isWindows => !kIsWeb && Platform.isWindows;
  static bool get isDesktop => !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);
  static bool get isMobile => !kIsWeb && (Platform.isAndroid || Platform.isIOS);
}
