import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../errors/app_exception.dart';
import '../models/message.dart';

/// Text channel messaging: history (keyset pagination) + realtime inserts.
class MessageRepository {
  MessageRepository(this._client);

  final SupabaseClient _client;

  /// Load one page of history, newest-first. [before] is the keyset
  /// cursor (created_at of the oldest loaded message); null = first page.
  Future<List<Message>> loadPage({
    required String channelId,
    DateTime? before,
    int limit = 50,
  }) async {
    try {
      var query = _client
          .from('messages')
          .select()
          .eq('channel_id', channelId);
      if (before != null) {
        query = query.lt('created_at', before.toIso8601String());
      }
      final data = await query
          .order('created_at', ascending: false)
          .limit(limit);
      // Return oldest-first for UI rendering.
      final msgs = data.map(Message.fromJson).toList();
      return msgs.reversed.toList();
    } catch (e) {
      throw AppErrors.from(e, context: 'Failed to load messages');
    }
  }

  Future<Message> send({
    required String channelId,
    required String senderId,
    required String content,
  }) async {
    try {
      final data = await _client
          .from('messages')
          .insert({
            'channel_id': channelId,
            'sender_id': senderId,
            'content': content,
          })
          .select()
          .single();
      return Message.fromJson(data);
    } catch (e) {
      throw AppErrors.from(e, context: 'Failed to send message');
    }
  }

  /// Realtime stream of newly INSERTED messages in [channelId].
  /// RLS applies: only members receive events. Caller owns the returned
  /// StreamSubscription and MUST cancel it (usually in dispose()).
  Stream<Message> subscribeMessages(String channelId) {
    final uid = _client.auth.currentUser!.id;
    return _client
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('channel_id', channelId)
        .map((rows) => rows.whereType<Map<String, dynamic>>())
        .asyncExpand((rows) async* {
          for (final row in rows) {
            yield Message.fromJson(row);
          }
        })
        .where((m) => m.senderId != uid || true); // include own (echo suppressed at UI)
  }

  Future<void> deleteMessage(String messageId) async {
    try {
      await _client.from('messages').delete().eq('id', messageId);
    } catch (e) {
      throw AppErrors.from(e, context: 'Failed to delete message');
    }
  }
}
