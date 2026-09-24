import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/voice_participant.dart';
import '../../core/state/providers.dart';

/// Live list of participants in one voice channel (Supabase Realtime on
/// the voice_participants table). Rendered under each voice channel in
/// the sidebar.
class VoiceChannelParticipants extends ConsumerStatefulWidget {
  const VoiceChannelParticipants({super.key, required this.channelId});

  final String channelId;

  @override
  ConsumerState<VoiceChannelParticipants> createState() =>
      _VoiceChannelParticipantsState();
}

class _VoiceChannelParticipantsState
    extends ConsumerState<VoiceChannelParticipants> {
  StreamSubscription<List<Map<String, dynamic>>>? _sub;
  List<VoiceParticipant> _participants = [];

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  void _subscribe() {
    final client = ref.read(supabaseClientProvider);
    _sub = client
        .from('voice_participants')
        .stream(primaryKey: ['channel_id', 'profile_id'])
        .eq('channel_id', widget.channelId)
        .listen((rows) {
      if (!mounted) return;
      setState(() {
        _participants =
            rows.map(VoiceParticipant.fromDbJson).toList();
      });
    });
  }

  @override
  void didUpdateWidget(VoiceChannelParticipants old) {
    super.didUpdateWidget(old);
    if (old.channelId != widget.channelId) {
      _sub?.cancel();
      _participants = [];
      _subscribe();
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_participants.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(left: 34),
      child: Column(
        children: [
          for (final p in _participants)
            Text(
              p.profileId.substring(0, 8),
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).hintColor,
              ),
            ),
        ],
      ),
    );
  }
}
