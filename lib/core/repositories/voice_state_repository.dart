import 'package:supabase_flutter/supabase_flutter.dart';

import '../errors/app_exception.dart';
import '../models/voice_participant.dart';

/// Tracks who is connected to which voice channel via the
/// `voice_participants` table (mirrors LiveKit occupancy; the
/// authoritative cap is enforced server-side in the edge function).
class VoiceStateRepository {
  VoiceStateRepository(this._client);

  final SupabaseClient _client;

  Future<List<VoiceParticipant>> listForServer(String serverId) async {
    try {
      final data = await _client
          .from('voice_participants')
          .select()
          .eq('server_id', serverId);
      return data.map(VoiceParticipant.fromDbJson).toList();
    } catch (e) {
      throw AppErrors.from(e, context: 'Failed to load voice participants');
    }
  }

  Future<void> markJoined({
    required String channelId,
    required String serverId,
  }) async {
    try {
      final uid = _client.auth.currentUser!.id;
      await _client.from('voice_participants').upsert({
        'channel_id': channelId,
        'profile_id': uid,
        'server_id': serverId,
      });
    } catch (e) {
      throw AppErrors.from(e, context: 'Failed to mark voice join');
    }
  }

  Future<void> markLeft() async {
    try {
      final uid = _client.auth.currentUser!.id;
      await _client.from('voice_participants').delete().eq('profile_id', uid);
    } catch (e) {
      throw AppErrors.from(e, context: 'Failed to mark voice leave');
    }
  }

  /// Realtime updates for the participants list. RLS limits rows to
  /// members of the same server. Caller owns the subscription.
  Stream<List<VoiceParticipant>> subscribeServerParticipants(
      String serverId) {
    return _client
        .from('voice_participants')
        .stream(primaryKey: ['channel_id', 'profile_id'])
        .eq('server_id', serverId)
        .map((rows) => rows
            .whereType<Map<String, dynamic>>()
            .map(VoiceParticipant.fromDbJson)
            .toList());
  }
}
