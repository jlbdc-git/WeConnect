import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../errors/app_exception.dart';
import '../models/user_settings.dart';

/// Settings live in two places:
///  • SharedPreferences — instant local load, offline, per-device.
///  • user_settings table — sync across the user's devices.
/// Writes go to both; reads prefer the local copy (fast path).
class SettingsRepository {
  SettingsRepository(this._client, this._prefs);

  final SupabaseClient _client;
  final SharedPreferences _prefs;

  static const _key = 'user_settings_v1';

  UserSettings loadLocal() {
    final raw = _prefs.getString(_key);
    if (raw == null) return const UserSettings();
    try {
      return UserSettings.fromDbJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return const UserSettings();
    }
  }

  Future<void> save(UserSettings s) async {
    // 1. local, immediately (optimistic)
    await _prefs.setString(_key, jsonEncode(s.toDbJson()));
    // 2. remote, best-effort (syncs to other devices; RLS: own row only)
    try {
      final uid = _client.auth.currentUser!.id;
      await _client.from('user_settings').upsert({
        'id': uid,
        ...s.toDbJson(),
      });
    } catch (e) {
      // Non-fatal: local save already succeeded. Surface for debugging.
      assert(() {
        // ignore: avoid_print
        print('[SettingsRepository] remote sync failed: $e');
        return true;
      }());
    }
  }

  /// Pull the remote copy (e.g. on login) and reconcile to local.
  Future<UserSettings> syncFromRemote() async {
    try {
      final uid = _client.auth.currentUser!.id;
      final data =
          await _client.from('user_settings').select().eq('id', uid).maybeSingle();
      if (data == null) return loadLocal();
      final remote = UserSettings.fromDbJson(data);
      // Remote is authoritative after login; adopt it locally.
      await _prefs.setString(_key, jsonEncode(remote.toDbJson()));
      return remote;
    } catch (e) {
      throw AppErrors.from(e, context: 'Settings sync failed');
    }
  }
}
