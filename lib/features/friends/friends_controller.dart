import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../core/models/friendship.dart';
import '../../core/state/providers.dart';

/// Friends list with pending requests, updated via Supabase Realtime.
class FriendsController extends AutoDisposeAsyncNotifier<List<FriendEntry>> {
  StreamSubscription<List<Map<String, dynamic>>>? _sub;

  @override
  Future<List<FriendEntry>> build() async {
    final client = ref.watch(supabaseClientProvider);
    final uid = client.auth.currentUser?.id;
    if (uid == null) return [];

    ref.onDispose(() {
      _sub?.cancel();
      _sub = null;
    });

    // Initial load.
    final entries =
        await ref.read(friendRepositoryProvider).listEntries(uid);

    // Realtime: any change to a friendship row involving me refreshes.
    // (Simple and correct: refetch the small list on any change.)
    _sub = client
        .from('friendships')
        .stream(primaryKey: ['id'])
        .order('created_at')
        .listen((rows) {
          final relevant = rows.any((r) =>
              r['requester_id'] == uid || r['addressee_id'] == uid);
          if (relevant) {
            // Fire-and-forget refresh; state updates when it completes.
            _refresh(uid);
          }
        });

    return entries;
  }

  Future<void> _refresh(String uid) async {
    try {
      final entries =
          await ref.read(friendRepositoryProvider).listEntries(uid);
      state = AsyncData(entries);
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }

  Future<void> sendRequest(String username) async {
    final client = ref.read(supabaseClientProvider);
    final me = client.auth.currentUser!.id;
    // Resolve username → profile id.
    final rows = await client
        .from('profiles')
        .select('id')
        .eq('username', username.trim().toLowerCase())
        .limit(1);
    if (rows.isEmpty) {
      throw const AppException('user_not_found',
          message: 'No user with that username.');
    }
    final targetId = rows.first['id'] as String;
    await ref.read(friendRepositoryProvider).sendRequest(toUserId: targetId);
    await _refresh(me);
  }

  Future<void> respond(String friendshipId, bool accept) async {
    final uid = ref.read(supabaseClientProvider).auth.currentUser!.id;
    await ref
        .read(friendRepositoryProvider)
        .respondRequest(friendshipId: friendshipId, accept: accept);
    await _refresh(uid);
  }

  Future<void> remove(String friendshipId) async {
    final uid = ref.read(supabaseClientProvider).auth.currentUser!.id;
    await ref.read(friendRepositoryProvider).remove(friendshipId);
    await _refresh(uid);
  }

  /// Search profiles by username prefix.
  Future<List<FriendEntry>> search(String query) async {
    final repo = ref.read(profileRepositoryProvider);
    final uid = ref.read(supabaseClientProvider).auth.currentUser!.id;
    final profiles = await repo.search(query);
    // Map to FriendEntry-shaped results (no friendship yet) for the UI.
    return profiles
        .where((p) => p.id != uid)
        .map((p) => FriendEntry(
              friendship: Friendship(
                id: '',
                requesterId: '',
                addresseeId: '',
                status: FriendshipStatus.declined, // sentinel: "not friends"
                createdAt: DateTime.now(),
                updatedAt: DateTime.now(),
              ),
              profile: p,
            ))
        .toList();
  }
}

final friendsControllerProvider = AutoDisposeAsyncNotifierProvider<
    FriendsController, List<FriendEntry>>(FriendsController.new);
