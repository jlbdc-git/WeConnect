import 'package:supabase_flutter/supabase_flutter.dart';

import '../errors/app_exception.dart';
import '../models/server.dart';

/// Server + channel + membership operations.
class ServerRepository {
  ServerRepository(this._client);

  final SupabaseClient _client;

  /// Servers the current user belongs to.
  Future<List<Server>> listMine() async {
    try {
      final user = _client.auth.currentUser;

      if (user == null) {
        throw const AppException(
          'auth_required',
          message: 'Sign in to load your servers.',
        );
      }

      final uid = user.id;
      final authContext =
          await _client.rpc<Map<String, dynamic>>(
        'debug_auth_context',
      );

      print('FLUTTER USER ID: $uid');
      print('SUPABASE AUTH CONTEXT: $authContext');
      
      final data = await _client
          .from('server_members')
          .select('server:servers!inner(*)')
          .eq('profile_id', uid);

      return data
          .map(
            (row) => Server.fromJson(
              row['server'] as Map<String, dynamic>,
            ),
          )
          .toList();
    } catch (e) {
      if (e is AppException) rethrow;

      throw AppErrors.from(
        e,
        context: 'Failed to load servers',
      );
    }
  }

  /// Creates a new server owned by the currently authenticated user.
  Future<Server> create({required String name}) async {
    try {
      // ------------------------------------------------------------
      // 1. Verify that the Flutter client has an authenticated user.
      // ------------------------------------------------------------
      final user = _client.auth.currentUser;

      if (user == null) {
        throw const AppException(
          'auth_required',
          message: 'Sign in to create a server.',
        );
      }

      // ------------------------------------------------------------
      // 2. Verify that an active Supabase session exists.
      // ------------------------------------------------------------
      final session = _client.auth.currentSession;

      if (session == null || session.accessToken.isEmpty) {
        throw const AppException(
          'auth_required',
          message:
              'Your login session is no longer valid. Please sign in again.',
        );
      }

      final uid = user.id;

      // Temporary diagnostics.
      // These are safe for development and help diagnose the 42501 error.
      print('CREATE SERVER');
      print('User ID: $uid');
      print(
        'Session exists: ${_client.auth.currentSession != null}',
      );
      print(
        'Access token exists: ${session.accessToken.isNotEmpty}',
      );

      // ------------------------------------------------------------
      // 3. Validate the server name.
      // ------------------------------------------------------------
      final serverName = name.trim();

      if (serverName.isEmpty) {
        throw const AppException(
          'invalid_server_name',
          message: 'Server name cannot be empty.',
        );
      }

      // ------------------------------------------------------------
      // 4. Insert the server.
      //
      // Supabase RLS policy:
      //
      //   WITH CHECK (owner_id = auth.uid())
      //
      // Therefore owner_id MUST be the authenticated user's ID.
      // ------------------------------------------------------------
      final data = await _client
          .from('servers')
          .insert({
            'name': serverName,
            'owner_id': uid,
          })
          .select()
          .single();

      return Server.fromJson(data);
    } on PostgrestException catch (e) {
      print('CREATE SERVER POSTGRES ERROR');
      print('Code: ${e.code}');
      print('Message: ${e.message}');
      print('Details: ${e.details}');
      print('Hint: ${e.hint}');

      // PostgreSQL RLS violation.
      if (e.code == '42501') {
        throw const AppException(
          'server_forbidden',
          message:
              'Supabase rejected server creation because of its security policy. '
              'Please sign out, sign back in, and try again.',
        );
      }

      throw AppErrors.from(
        e,
        context: 'Failed to create server',
      );
    } on AppException {
      rethrow;
    } catch (e) {
      throw AppErrors.from(
        e,
        context: 'Failed to create server',
      );
    }
  }

  /// Join via invite code.
  Future<Server> joinByCode(String code) async {
    try {
      final user = _client.auth.currentUser;

      if (user == null) {
        throw const AppException(
          'auth_required',
          message: 'Sign in to join a server.',
        );
      }

      final cleanCode = code.trim();

      if (cleanCode.isEmpty) {
        throw const AppException(
          'invalid_invite_code',
          message: 'Enter an invite code.',
        );
      }

      final serverId = await _client.rpc<String>(
        'join_server_by_code',
        params: {
          'p_code': cleanCode,
        },
      );

      final data = await _client
          .from('servers')
          .select()
          .eq('id', serverId)
          .single();

      return Server.fromJson(data);
    } on PostgrestException catch (e) {
      if (e.message.contains('SERVER_NOT_FOUND')) {
        throw const AppException(
          'server_not_found',
          message: 'No server matches that invite code.',
        );
      }

      throw AppException(
        'server_join_failed',
        cause: e,
      );
    } on AppException {
      rethrow;
    } catch (e) {
      throw AppErrors.from(
        e,
        context: 'Failed to join server',
      );
    }
  }

  Future<void> leave(String serverId) =>
      _safeRpc('leave_server', {
        'p_server_id': serverId,
      });

  /// Loads all channels belonging to a server.
  Future<List<Channel>> listChannels(String serverId) async {
    try {
      final data = await _client
          .from('channels')
          .select()
          .eq('server_id', serverId)
          .order('position');

      return data.map(Channel.fromJson).toList();
    } catch (e) {
      throw AppErrors.from(
        e,
        context: 'Failed to load channels',
      );
    }
  }

  /// Creates a text or voice channel.
  Future<Channel> createChannel({
    required String serverId,
    required String name,
    required bool isVoice,
  }) async {
    try {
      final cleanName = name.trim();

      if (cleanName.isEmpty) {
        throw const AppException(
          'invalid_channel_name',
          message: 'Channel name cannot be empty.',
        );
      }

      final safeName = cleanName
          .toLowerCase()
          .replaceAll(RegExp(r'\s+'), '-');

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
    } on AppException {
      rethrow;
    } catch (e) {
      throw AppErrors.from(
        e,
        context: 'Failed to create channel',
      );
    }
  }

  /// Lists members of a server.
  Future<List<ServerMember>> listMembers(String serverId) async {
    try {
      final data = await _client
          .from('server_members')
          .select()
          .eq('server_id', serverId);

      return data.map(ServerMember.fromJson).toList();
    } catch (e) {
      throw AppErrors.from(
        e,
        context: 'Failed to load members',
      );
    }
  }

  /// Executes a server RPC safely.
  Future<void> _safeRpc(
    String fn,
    Map<String, dynamic> params,
  ) async {
    try {
      await _client.rpc<void>(
        fn,
        params: params,
      );
    } catch (e) {
      throw AppErrors.from(
        e,
        context: 'RPC $fn failed',
      );
    }
  }
}