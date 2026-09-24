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
  String? _joinError;

  @override
  void initState() {
    super.initState();
    // Auto-join when the panel opens.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _join();
    });
  }

  @override
  void didUpdateWidget(VoicePanel old) {
    super.didUpdateWidget(old);
    // Switching to a different voice channel joins the new one.
    if (old.channelId != widget.channelId) {
      _joinError = null;
      _join();
    }
  }

  Future<void> _join() async {
    try {
      await ref
          .read(voiceControllerProvider.notifier)
          .join(widget.channelId, widget.serverId);
      if (mounted) setState(() => _joinError = null);
    } catch (e) {
      if (mounted) setState(() => _joinError = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final voice = ref.watch(voiceControllerProvider);
    final state = voice.valueOrNull ?? const VoiceState();
    final settings = ref.watch(settingsControllerProvider).valueOrNull;
    final isPtt = settings?.voiceMode == VoiceMode.pushToTalk;
    final isAndroid = Platform.isAndroid;

    return Scaffold(
      appBar: AppBar(title: const Text('Voice Channel')),
      body: Center(
        child: Column(
          children: [
            SizedBox(
              height: 96,
              child: _ConnectionBar(
                state: state,
                joinError: _joinError,
                onRetry: _joinError == null ? null : _join,
              ),
            ),
            Expanded(
              child: _ParticipantGrid(state: state),
            ),
            if (isAndroid && isPtt)
              const _AndroidPttButton(),
            _VoiceControls(state: state),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

class _ConnectionBar extends StatelessWidget {
  const _ConnectionBar({required this.state, this.joinError, this.onRetry});

  final VoiceState state;
  final String? joinError;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    if (joinError != null) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 18, color: Colors.red.shade300),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              joinError!,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
              style: TextStyle(color: Colors.red.shade300, fontSize: 12),
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      );
    }
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
    final myName = profilesAsync.valueOrNull?.effectiveName ?? 'You';

    // Build a stable list: me + anyone the speaking map reports.
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
                    color: p.speaking ? Colors.green : Colors.transparent,
                    width: 3,
                  ),
                ),
                child: CircleAvatar(
                  radius: 28,
                  child: Text(
                    p.name.isNotEmpty ? p.name[0].toUpperCase() : '?',
                  ),
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
  const _VoiceControls({required this.state});

  final VoiceState state;

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
            backgroundColor: state.isMuted ? Colors.red.shade900 : null,
          ),
        ),
        const SizedBox(width: 12),
        IconButton.filledTonal(
          tooltip: state.isDeafened ? 'Undeafen' : 'Deafen',
          onPressed: () =>
              ref.read(voiceControllerProvider.notifier).toggleDeafen(),
          icon:
              Icon(state.isDeafened ? Icons.headset_off : Icons.headset),
          style: IconButton.styleFrom(
            backgroundColor: state.isDeafened ? Colors.red.shade900 : null,
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
///
/// Uses a Listener (pointer down/up/cancel) instead of long-press
/// recognizers: transmission starts on finger-down, not ~500 ms later when
/// the long-press timeout fires. The pressed notifier lives in State (not
/// per build) so a rebuild can't lose it.
class _AndroidPttButton extends ConsumerStatefulWidget {
  const _AndroidPttButton();

  @override
  ConsumerState<_AndroidPttButton> createState() => _AndroidPttButtonState();
}

class _AndroidPttButtonState extends ConsumerState<_AndroidPttButton> {
  final ValueNotifier<bool> _pressed = ValueNotifier<bool>(false);

  @override
  void dispose() {
    // Safety net: never leave the mic transmitting if the widget dies
    // mid-press (e.g. navigation away while holding).
    if (_pressed.value) {
      ref.read(voiceControllerProvider.notifier).setPttPressed(false);
    }
    _pressed.dispose();
    super.dispose();
  }

  void _setPressed(bool down) {
    _pressed.value = down;
    ref.read(voiceControllerProvider.notifier).setPttPressed(down);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(voiceControllerProvider).valueOrNull ??
        const VoiceState();
    return ValueListenableBuilder<bool>(
      valueListenable: _pressed,
      builder: (context, pressed, _) {
        return Listener(
          onPointerDown: (_) => _setPressed(true),
          onPointerUp: (_) => _setPressed(false),
          onPointerCancel: (_) => _setPressed(false),
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
