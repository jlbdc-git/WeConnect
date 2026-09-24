import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../errors/app_exception.dart';
import '../models/profile.dart';

/// Data access for profiles: fetch, search, update, avatar upload.
class ProfileRepository {
  ProfileRepository(this._client);

  final SupabaseClient _client;

  Future<Profile> getById(String id) async {
    try {
      final data = await _client
          .from('profiles')
          .select()
          .eq('id', id)
          .single();
      return Profile.fromJson(data);
    } catch (e) {
      throw AppErrors.from(e, context: 'Failed to load profile');
    }
  }

  Future<List<Profile>> getByIds(List<String> ids) async {
    if (ids.isEmpty) return [];
    try {
      final data = await _client.from('profiles').select().inFilter('id', ids);
      return data.map(Profile.fromJson).toList();
    } catch (e) {
      throw AppErrors.from(e, context: 'Failed to load profiles');
    }
  }

  /// Search by exact username (case-insensitive, citext) or display name.
  Future<List<Profile>> search(String query, {int limit = 10}) async {
    final q = query.trim();
    if (q.length < 3) return [];
    try {
      final data = await _client
          .from('profiles')
          .select()
          .ilike('username', '%$q%')
          .limit(limit);
      return data.map(Profile.fromJson).toList();
    } catch (e) {
      throw AppErrors.from(e, context: 'Search failed');
    }
  }

  /// Update own profile fields (id/username/tag are blocked by trigger).
  Future<Profile> update({
    required String id,
    String? displayName,
    String? avatarUrl,
  }) async {
    try {
      final patch = <String, dynamic>{};
      if (displayName != null) patch['display_name'] = displayName;
      if (avatarUrl != null) patch['avatar_url'] = avatarUrl;
      final data = await _client
          .from('profiles')
          .update(patch)
          .eq('id', id)
          .select()
          .single();
      return Profile.fromJson(data);
    } catch (e) {
      throw AppErrors.from(e, context: 'Update profile failed');
    }
  }

  /// Upload avatar to the `avatars` storage bucket (path: `{uid}/avatar.png`).
  Future<String> uploadAvatar({
    required String userId,
    required String filePath,
  }) async {
    try {
      final file = await File(filePath).readAsBytes();
      const bucket = 'avatars';
      final path = '$userId/avatar.png';
      await _client.storage.from(bucket).uploadBinary(
            path,
            file,
            fileOptions: const FileOptions(upsert: true, contentType: 'image/png'),
          );
      return _client.storage.from(bucket).getPublicUrl(path);
    } catch (e) {
      throw AppErrors.from(e, context: 'Avatar upload failed');
    }
  }
}
