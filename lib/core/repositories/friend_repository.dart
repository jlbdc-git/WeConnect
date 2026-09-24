import 'package:supabase_flutter/supabase_flutter.dart';

import '../errors/app_exception.dart';
import '../models/friendship.dart';
import '../models/profile.dart';

/// Friend/request operations. All state lives in the `friendships` table,
/// protected by RLS: you can only ever see rows involving you.
class FriendRepository {
  FriendRepository(this._client);

  final SupabaseClient _client;

  /// All friendships involving the current user, with the other user's
  /// embedded profile (single round trip, no N+1).
  ///
  /// NOTE: the hints must reference the FK constraints created in migration
  /// 0001 (`friendships_requester_id_fkey` / `friendships_addressee_id_fkey`,
  /// auto-named by Postgres from table + column). Both columns reference the
  /// SAME table, so the unambiguous column-name hint (`profiles!requester_id`)
  /// is not available — the constraint-name form is required and verified
  /// against the migration.
  Future<List<FriendEntry>> listEntries(String viewerId) async {
    try {
      final data = await _client
          .from('friendships')
          .select(
              '*, requester:profiles!friendships_requester_id_fkey(*), addressee:profiles!friendships_addressee_id_fkey(*)')
          .or('requester_id.eq.$viewerId,addressee_id.eq.$viewerId')
          .order('created_at', ascending: false);
      return data.map((row) {
        final f = Friendship.fromJson(row);
        final otherJson = (f.otherUser(viewerId) == f.requesterId
                ? row['requester']
                : row['addressee']) as Map<String, dynamic>;
        return FriendEntry(friendship: f, profile: Profile.fromJson(otherJson));
      }).toList();
    } catch (e) {
      throw AppErrors.from(e, context: 'Failed to load friends');
    }
  }

  /// Send a friend request.
  ///
  /// Pair-uniqueness is enforced by the `friendships_pair_unique` expression
  /// index (least/greatest); the true direction lives in the columns so RLS
  /// knows who must accept.
  Future<void> sendRequest({required String toUserId}) async {
    try {
      final me = _client.auth.currentUser!.id;
      if (me == toUserId) {
        throw const AppException(
          'friend_self',
          message: "You can't add yourself.",
        );
      }
      // Pre-check both directions for a friendlier duplicate error.
      // The DB's unique constraint remains the authoritative guard.
      final existing = await _client
          .from('friendships')
          .select('id')
          .or(
              'and(requester_id.eq.$me,addressee_id.eq.$toUserId),and(requester_id.eq.$toUserId,addressee_id.eq.$me)');
      if (existing.isNotEmpty) {
        throw const AppException(
          'friend_exists',
          message: 'You are already friends or a request is pending.',
        );
      }
      // TRUE direction: requester_id = the sender (me). The DB's
      // expression unique index treats (a,b)/(b,a) as the same pair, so
      // duplicates are impossible in either direction, while RLS still
      // knows who must accept (addressee).
      await _client.from('friendships').insert({
        'requester_id': me,
        'addressee_id': toUserId,
        'status': 'pending',
      });
    } on AppException {
      rethrow;
    } catch (e) {
      throw AppErrors.from(e, context: 'Friend request failed');
    }
  }

  /// Accept or decline a pending request (addressee only, per RLS).
  Future<void> respondRequest({
    required String friendshipId,
    required bool accept,
  }) async {
    try {
      await _client
          .from('friendships')
          .update({'status': accept ? 'accepted' : 'declined'})
          .eq('id', friendshipId);
    } catch (e) {
      throw AppErrors.from(e, context: 'Failed to update friend request');
    }
  }

  /// Remove friend or cancel an outgoing request (either party, per RLS).
  Future<void> remove(String friendshipId) async {
    try {
      await _client.from('friendships').delete().eq('id', friendshipId);
    } catch (e) {
      throw AppErrors.from(e, context: 'Failed to remove friend');
    }
  }
}
