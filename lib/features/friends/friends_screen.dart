import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/friendship.dart';
import '../friends/friends_controller.dart';

class FriendsScreen extends ConsumerStatefulWidget {
  const FriendsScreen({super.key});

  @override
  ConsumerState<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends ConsumerState<FriendsScreen> {
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final friendsAsync = ref.watch(friendsControllerProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Friends')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddFriendDialog(context),
        icon: const Icon(Icons.person_add_alt),
        label: const Text('Add friend'),
      ),
      body: friendsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (entries) {
          final incoming = entries
              .where((e) => e.isPending && e.isIncoming)
              .toList();
          final outgoing = entries
              .where((e) => e.isPending && !e.isIncoming)
              .toList();
          final friends =
              entries.where((e) => e.isAccepted).toList();

          return ListView(
            padding: const EdgeInsets.only(bottom: 88),
            children: [
              if (incoming.isNotEmpty) ...[
                _section(context, 'FRIEND REQUESTS'),
                for (final e in incoming)
                  _RequestTile(entry: e),
              ],
              if (outgoing.isNotEmpty) ...[
                _section(context, 'PENDING'),
                for (final e in outgoing)
                  ListTile(
                    leading: const CircleAvatar(
                        child: Icon(Icons.person)),
                    title: Text(e.profile.effectiveName),
                    subtitle: Text('@${e.profile.username}'),
                    trailing: TextButton(
                      onPressed: () => ref
                          .read(friendsControllerProvider.notifier)
                          .remove(e.friendship.id),
                      child: const Text('Cancel'),
                    ),
                  ),
              ],
              _section(context, 'ALL FRIENDS'),
              if (friends.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'No friends yet. Add someone by their username.',
                    style: TextStyle(color: theme.hintColor),
                    textAlign: TextAlign.center,
                  ),
                ),
              for (final e in friends)
                ListTile(
                  leading: const CircleAvatar(
                      child: Icon(Icons.person)),
                  title: Text(e.profile.effectiveName),
                  subtitle: Text('@${e.profile.username}'),
                  trailing: IconButton(
                    tooltip: 'Remove friend',
                    icon: const Icon(Icons.person_remove_alt_1, size: 20),
                    onPressed: () => ref
                        .read(friendsControllerProvider.notifier)
                        .remove(e.friendship.id),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _section(BuildContext context, String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: Theme.of(context).hintColor,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Future<void> _showAddFriendDialog(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final ctrl = TextEditingController();
    final sent = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add friend'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Enter a username',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Send request')),
        ],
      ),
    );
    if (sent != true) return;

    try {
      await ref
          .read(friendsControllerProvider.notifier)
          .sendRequest(ctrl.text);
      messenger.showSnackBar(
        const SnackBar(content: Text('Friend request sent.')),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }
}

class _RequestTile extends ConsumerWidget {
  const _RequestTile({required this.entry});

  final FriendEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      leading: const CircleAvatar(child: Icon(Icons.person)),
      title: Text(entry.profile.effectiveName),
      subtitle: Text('@${entry.profile.username}'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Accept',
            icon: const Icon(Icons.check, color: Colors.green),
            onPressed: () => ref
                .read(friendsControllerProvider.notifier)
                .respond(entry.friendship.id, true),
          ),
          IconButton(
            tooltip: 'Decline',
            icon: const Icon(Icons.close, color: Colors.red),
            onPressed: () => ref
                .read(friendsControllerProvider.notifier)
                .respond(entry.friendship.id, false),
          ),
        ],
      ),
    );
  }
}
