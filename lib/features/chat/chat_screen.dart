import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/message.dart';
import '../../core/state/providers.dart';
import 'chat_controller.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({
    super.key,
    required this.channelId,
    required this.serverId,
  });

  final String channelId;
  final String serverId;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _composerCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(() {
      // Load older when scrolled to the top.
      if (_scrollCtrl.hasClients &&
          _scrollCtrl.position.pixels <= 200 &&
          !_scrollCtrl.position.outOfRange) {
        ref.read(chatControllerProvider(widget.channelId).notifier).loadOlder();
      }
    });
  }

  @override
  void dispose() {
    _composerCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
      }
    });
  }

  Future<void> _send() async {
    final text = _composerCtrl.text;
    _composerCtrl.clear();
    try {
      await ref.read(chatControllerProvider(widget.channelId).notifier).send(text);
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
        _composerCtrl.text = text; // restore the draft
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final messagesAsync = ref.watch(chatControllerProvider(widget.channelId));
    final myId = ref.watch(supabaseClientProvider).auth.currentUser?.id;

    return Scaffold(
      appBar: AppBar(title: const Text('# channel')),
      body: Column(
        children: [
          Expanded(
            child: messagesAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('$e')),
              data: (messages) {
                _scrollToBottom();
                return ListView.builder(
                  controller: _scrollCtrl,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  itemCount: messages.length,
                  itemBuilder: (context, i) {
                    final m = messages[i];
                    final isMine = m.senderId == myId;
                    final showAuthor = i == 0 ||
                        messages[i - 1].senderId != m.senderId;
                    return _MessageTile(
                      message: m,
                      isMine: isMine,
                      showAuthor: showAuthor,
                    );
                  },
                );
              },
            ),
          ),
          const Divider(height: 1),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _composerCtrl,
                      minLines: 1,
                      maxLines: 5,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: const InputDecoration(
                        hintText: 'Message #channel',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    tooltip: 'Send',
                    onPressed: _send,
                    icon: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageTile extends StatelessWidget {
  const _MessageTile({
    required this.message,
    required this.isMine,
    required this.showAuthor,
  });

  final Message message;
  final bool isMine;
  final bool showAuthor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showAuthor)
            const CircleAvatar(
              radius: 16,
              child: Icon(Icons.person, size: 18),
            )
          else
            const SizedBox(width: 32),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (showAuthor)
                  Text(
                    isMine ? 'You' : message.senderId.substring(0, 8),
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: isMine
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurface,
                    ),
                  ),
                Text(message.content),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
