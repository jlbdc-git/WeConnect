import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/user_settings.dart';
import '../../core/services/voice_service.dart';
import '../../core/state/providers.dart';
import '../settings/settings_controller.dart';
import '../voice/voice_controller.dart';

/// Main voice channel view: join/leave, participants with speaking rings,
/// mute/deafen controls, and the large PTT button on Android.
class VoicePanel extends ConsumerStatefulWidget {
  const VoicePanel({
    super.key,
    required this.channelId,
    required this.serverId,
  });

  final String channelId;
  final String serverId;

  @override
  ConsumerState<VoicePanel> createState() => _VoicePanelState();
}

class _VoicePanelState extends ConsumerState<VoicePanel> {
  @override
  void initState() {
    super.initState();
    // Auto-join when the panel opens.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(voiceControllerProvider.notifier)
          .join(widget.channelId, widget.serverId);
    });
  }

  @override
  void dispose() {
    // Leaving happens via the Leave button; auto-leave on dispose would
    // fight re-renders, so it's explicit. (Discord behaves the same.)
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final voice = ref.watch(voiceControllerProvider);
    final state = voice.valueOrNull ?? const VoiceState();
    final settings = ref.watch(settingsControllerProvider).valueOrNull;
    final isPtt = settings?.voiceMode == VoiceMode.pushToTalk;
    final isAndroid = !Platform.isAndroid ? false : true;

    return Scaffold(
      appBar: AppBar(title: const Text('Voice Channel')),
      body: Center(
        child: Column(
          children: [
            SizedBox(
              height: 96,
              child: _ConnectionBar(state: state),
            ),
            Expanded(
              child: _ParticipantGrid(state: state),
            ),
            if (isAndroid && isPtt)
              _AndroidPttButton(state: state),
            _VoiceControls(state: state, channelId: widget.channelId),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

class _ConnectionBar extends StatelessWidget {
  const _ConnectionBar({required this.state});

  final VoiceState state;

  @override
  Widget build(BuildContext context) {
    final label = switch (state.connState) {
      VoiceConnState.connected => 'Voice connected',
      VoiceConnState.connecting => 'Connecting…',
      VoiceConnState.reconnecting => 'Reconnecting…',
      VoiceConnState.failed => 'Connection failed',
      VoiceConnState.disconnected => 'Not connected',
    };
    final color = switch (state.connState) {
      VoiceConnState.connected => Colors.green,
      VoiceConnState.reconnecting => Colors.orange,
      VoiceConnState.failed => Colors.red,
      _ => Colors.grey,
    };
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.circle, size: 10, color: color),
        const SizedBox(width: 6),
        Text(label),
      ],
    );
  }
}

class _ParticipantGrid extends ConsumerWidget {
  const _ParticipantGrid({required this.state});

  final VoiceState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final myId = ref.watch(supabaseClientProvider).auth.currentUser?.id ?? '';
    final profilesAsync = ref.watch(myProfileProvider);
    final myName =
        profilesAsync.valueOrNull?.effectiveName ?? 'You';

    // Build a stable list: me + anyone speaking map reports.
    final entries = <_Participant>[
      _Participant(
        id: myId,
        name: myName,
        speaking: state.speaking[myId] ?? false,
        muted: state.isMuted,
      ),
      for (final entry in state.speaking.entries)
        if (entry.key != myId)
          _Participant(
            id: entry.key,
            name: entry.key.substring(0, 8),
            speaking: entry.value,
            muted: false,
          ),
    ];

    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      children: [
        for (final p in entries)
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: p.speaking
                        ? Colors.green
                        : Colors.transparent,
                    width: 3,
                  ),
                ),
                child: CircleAvatar(
                  radius: 28,
                  child: Text(p.name[0].toUpperCase()),
                ),
              ),
              const SizedBox(height: 6),
              Text(p.name, overflow: TextOverflow.ellipsis),
              if (p.muted)
                const Icon(Icons.mic_off, size: 14, color: Colors.red),
            ],
          ),
      ],
    );
  }
}

class _Participant {
  const _Participant({
    required this.id,
    required this.name,
    required this.speaking,
    required this.muted,
  });

  final String id;
  final String name;
  final bool speaking;
  final bool muted;
}

class _VoiceControls extends ConsumerWidget {
  const _VoiceControls({required this.state, required this.channelId});

  final VoiceState state;
  final String channelId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton.filledTonal(
          tooltip: state.isMuted ? 'Unmute' : 'Mute',
          onPressed: () =>
              ref.read(voiceControllerProvider.notifier).toggleMute(),
          icon: Icon(state.isMuted ? Icons.mic_off : Icons.mic),
          style: IconButton.styleFrom(
            backgroundColor:
                state.isMuted ? Colors.red.shade900 : null,
          ),
        ),
        const SizedBox(width: 12),
        IconButton.filledTonal(
          tooltip: state.isDeafened ? 'Undeafen' : 'Deafen',
          onPressed: () =>
              ref.read(voiceControllerProvider.notifier).toggleDeafen(),
          icon: Icon(state.isDeafened
              ? Icons.headset_off
              : Icons.headset),
          style: IconButton.styleFrom(
            backgroundColor:
                state.isDeafened ? Colors.red.shade900 : null,
          ),
        ),
        const SizedBox(width: 12),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: Colors.red.shade900,
          ),
          onPressed: () =>
              ref.read(voiceControllerProvider.notifier).leave(),
          icon: const Icon(Icons.call_end),
          label: const Text('Disconnect'),
        ),
      ],
    );
  }
}

/// Android: large press-and-hold PTT button.
class _AndroidPttButton extends ConsumerWidget {
  const _AndroidPttButton({required this.state});

  final VoiceState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pressedNotifier = ValueNotifier<bool>(false);

    return ValueListenableBuilder<bool>(
      valueListenable: pressedNotifier,
      builder: (context, pressed, _) {
        return GestureDetector(
          onLongPressStart: (_) {
            pressedNotifier.value = true;
            ref.read(voiceControllerProvider.notifier).setPttPressed(true);
          },
          onLongPressEnd: (_) {
            pressedNotifier.value = false;
            ref.read(voiceControllerProvider.notifier).setPttPressed(false);
          },
          onLongPressCancel: () {
            pressedNotifier.value = false;
            ref.read(voiceControllerProvider.notifier).setPttPressed(false);
          },
          child: Container(
            width: 132,
            height: 132,
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: state.isMuted
                  ? Colors.grey.shade800
                  : pressed
                      ? Colors.green.shade700
                      : Theme.of(context).colorScheme.primary,
              border: Border.all(
                color: pressed ? Colors.greenAccent : Colors.transparent,
                width: 4,
              ),
            ),
            child: Center(
              child: Text(
                state.isMuted ? 'MUTED' : pressed ? 'TALKING' : 'HOLD TO TALK',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
