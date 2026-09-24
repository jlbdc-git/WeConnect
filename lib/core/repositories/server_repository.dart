import 'package:supabase_flutter/supabase_flutter.dart';

import '../errors/app_exception.dart';
import '../models/server.dart';

/// Server + channel + membership operations.
class ServerRepository {
  ServerRepository(this._client);

  final SupabaseClient _client;

  /// Servers the current user belongs to (joined with members).
  Future<List<Server>> listMine() async {
    try {
      final uid = _client.auth.currentUser!.id;
      final data = await _client
          .from('server_members')
          .select('server:servers!inner(*)')
          .eq('profile_id', uid);
      return data
          .map((row) => Server.fromJson(row['server'] as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw AppErrors.from(e, context: 'Failed to load servers');
    }
  }

  Future<Server> create({required String name}) async {
    try {
      final uid = _client.auth.currentUser!.id;
      final data = await _client
          .from('servers')
          .insert({'name': name, 'owner_id': uid})
          .select()
          .single();
      return Server.fromJson(data);
    } catch (e) {
      throw AppErrors.from(e, context: 'Failed to create server');
    }
  }

  /// Join via invite code (RPC handles the race safely).
  Future<Server> joinByCode(String code) async {
    try {
      final serverId = await _client
          .rpc<String>('join_server_by_code', params: {'p_code': code});
      final data =
          await _client.from('servers').select().eq('id', serverId).single();
      return Server.fromJson(data);
    } on PostgrestException catch (e) {
      if (e.message.contains('SERVER_NOT_FOUND')) {
        throw const AppException(
          'server_not_found',
          message: 'No server matches that invite code.',
        );
      }
      throw AppException('server_join_failed', cause: e);
    } catch (e) {
      throw AppErrors.from(e, context: 'Failed to join server');
    }
  }

  Future<void> leave(String serverId) =>
      _safeRpc('leave_server', {'p_server_id': serverId});

  Future<List<Channel>> listChannels(String serverId) async {
    try {
      final data = await _client
          .from('channels')
          .select()
          .eq('server_id', serverId)
          .order('position');
      return data.map(Channel.fromJson).toList();
    } catch (e) {
      throw AppErrors.from(e, context: 'Failed to load channels');
    }
  }

  Future<Channel> createChannel({
    required String serverId,
    required String name,
    required bool isVoice,
  }) async {
    try {
      final safeName = name.trim().toLowerCase().replaceAll(' ', '-');
      final data = await _client
          .from('channels')
          .insert({
            'server_id': serverId,
            'name': safeName,
            'kind': isVoice ? 'voice' : 'text',
          })
          .select()
          .single();
      return Channel.fromJson(data);
    } catch (e) {
      throw AppErrors.from(e, context: 'Failed to create channel');
    }
  }

  Future<List<ServerMember>> listMembers(String serverId) async {
    try {
      final data =
          await _client.from('server_members').select().eq('server_id', serverId);
      return data.map(ServerMember.fromJson).toList();
    } catch (e) {
      throw AppErrors.from(e, context: 'Failed to load members');
    }
  }

  Future<void> _safeRpc(String fn, Map<String, dynamic> params) async {
    try {
      await _client.rpc<void>(fn, params: params);
    } catch (e) {
      throw AppErrors.from(e, context: 'RPC $fn failed');
    }
  }
}
