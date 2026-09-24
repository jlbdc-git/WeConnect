import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/message.dart';
import '../../core/state/providers.dart';

/// Messages for one channel: keyset-paginated history + realtime tail.
class ChatController
    extends AutoDisposeFamilyAsyncNotifier<List<Message>, String> {
  static const pageSize = 50;
  bool _hasMore = true;
  bool _loadingOlder = false;

  bool get hasMore => _hasMore;

  @override
  Future<List<Message>> build(String channelId) async {
    final page = await ref
        .read(messageRepositoryProvider)
        .loadPage(channelId: channelId);
    _hasMore = page.length >= pageSize;
    _subscribeRealtime(channelId);
    return page;
  }

  void _subscribeRealtime(String channelId) {
    // Keep the sub tied to this provider instance's lifecycle.
    final sub = ref
        .read(messageRepositoryProvider)
        .subscribeMessages(channelId)
        .listen((message) {
      final current = state.valueOrNull ?? [];
      // Skip duplicates (own inserts already appear via .select() single).
      if (current.any((m) => m.id == message.id)) return;
      state = AsyncData([...current, message]);
    });
    ref.onDispose(sub.cancel);
  }

  /// Load one older page (keyset cursor = oldest loaded created_at).
  Future<void> loadOlder() async {
    if (!_hasMore || _loadingOlder) return;
    final channelId = arg;
    final current = state.valueOrNull ?? [];
    if (current.isEmpty) return;
    _loadingOlder = true;
    try {
      final older = await ref.read(messageRepositoryProvider).loadPage(
            channelId: channelId,
            before: current.first.createdAt,
          );
      _hasMore = older.length >= pageSize;
      // Dedup (a realtime echo can race pagination).
      final existingIds = current.map((m) => m.id).toSet();
      final merged = [
        ...older.where((m) => !existingIds.contains(m.id)),
        ...current,
      ];
      state = AsyncData(merged);
    } finally {
      _loadingOlder = false;
    }
  }

  Future<void> send(String text) async {
    final client = ref.read(supabaseClientProvider);
    final uid = client.auth.currentUser!.id;
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    await ref.read(messageRepositoryProvider).send(
          channelId: arg,
          senderId: uid,
          content: trimmed,
        );
    // Optimistic append is skipped: the insert returns the row and
    // realtime echoes it; append-on-echo keeps ordering authoritative.
  }
}

final chatControllerProvider = AutoDisposeAsyncNotifierProviderFamily<
    ChatController, List<Message>, String>(ChatController.new);
