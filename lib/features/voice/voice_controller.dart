import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/user_settings.dart';
import '../../core/services/platform_service.dart';
import '../../core/services/voice_service.dart';
import '../../core/state/providers.dart';
import '../settings/settings_controller.dart';

/// App-facing voice state (mirrors VoiceService + settings).
class VoiceState {
  const VoiceState({
    this.connState = VoiceConnState.disconnected,
    this.speaking = const {},
    this.currentChannelId,
    this.currentServerId,
    this.isMuted = false,
    this.isDeafened = false,
  });

  final VoiceConnState connState;
  final Map<String, bool> speaking;
  final String? currentChannelId;
  final String? currentServerId;
  final bool isMuted;
  final bool isDeafened;

  VoiceState copyWith({
    VoiceConnState? connState,
    Map<String, bool>? speaking,
    String? currentChannelId,
    String? currentServerId,
    bool? isMuted,
    bool? isDeafened,
  }) {
    return VoiceState(
      connState: connState ?? this.connState,
      speaking: speaking ?? this.speaking,
      currentChannelId: currentChannelId ?? this.currentChannelId,
      currentServerId: currentServerId ?? this.currentServerId,
      isMuted: isMuted ?? this.isMuted,
      isDeafened: isDeafened ?? this.isDeafened,
    );
  }
}

class VoiceController extends AsyncNotifier<VoiceState> {
  StreamSubscription<VoiceConnState>? _stateSub;
  StreamSubscription<Map<String, bool>>? _speakingSub;

  @override
  Future<VoiceState> build() async {
    final service = ref.read(voiceServiceProvider);

    ref.onDispose(() {
      _stateSub?.cancel();
      _speakingSub?.cancel();
    });

    _stateSub ??= service.onConnState.listen((s) {
      final cur = state.valueOrNull ?? const VoiceState();
      state = AsyncData(cur.copyWith(
        connState: s,
        currentChannelId: service.currentChannelId,
        currentServerId: service.currentServerId,
        isMuted: service.isMuted,
        isDeafened: service.isDeafened,
      ));
    });

    _speakingSub ??= service.onSpeaking.listen((map) {
      final cur = state.valueOrNull ?? const VoiceState();
      state = AsyncData(cur.copyWith(speaking: map));
    });

    return VoiceState();
  }

  Future<void> join(String channelId, String serverId) async {
    final settings = ref.read(settingsControllerProvider).valueOrNull ??
        const UserSettings();
    try {
      await ref.read(voiceServiceProvider).join(
            channelId: channelId,
            serverId: serverId,
            pttMode: settings.voiceMode == VoiceMode.pushToTalk,
            vadSensitivity: settings.vadSensitivity,
            noiseSuppression: settings.noiseSuppression,
            echoCancellation: settings.echoCancellation,
            autoGainControl: settings.autoGainControl,
          );
      await PlatformService.setPttEnabled(
          settings.voiceMode == VoiceMode.pushToTalk);
    } catch (e) {
      rethrow;
    }
  }

  Future<void> leave() async {
    await PlatformService.setPttEnabled(false);
    await ref.read(voiceServiceProvider).leave();
  }

  Future<void> toggleMute() async {
    await ref.read(voiceServiceProvider).setMuted(!ref.read(voiceServiceProvider).isMuted);
    final service = ref.read(voiceServiceProvider);
    state = AsyncData((state.valueOrNull ?? const VoiceState())
        .copyWith(isMuted: service.isMuted));
  }

  void toggleDeafen() {
    final service = ref.read(voiceServiceProvider);
    service.setDeafened(!service.isDeafened);
    state = AsyncData((state.valueOrNull ?? const VoiceState())
        .copyWith(isDeafened: service.isDeafened));
  }

  void setPttPressed(bool down) =>
      ref.read(voiceServiceProvider).setPttPressed(down);

  void applySettings(UserSettings s) {
    ref.read(voiceServiceProvider).applySettings(
          pttMode: s.voiceMode == VoiceMode.pushToTalk,
          vadSensitivity: s.vadSensitivity,
        );
  }
}

final voiceControllerProvider =
    AsyncNotifierProvider<VoiceController, VoiceState>(VoiceController.new);

/// Windows virtual-key code lookup for PTT keys.
int pttKeyNameToVk(String name) {
  switch (name.toUpperCase()) {
    case 'SPACE':
      return 0x20;
    case 'LALT':
      return 0xA4;
    case 'RALT':
      return 0xA5;
    case 'LCTRL':
      return 0xA2;
    case 'RCTRL':
      return 0xA3;
    case 'LSHIFT':
      return 0xA0;
    case 'TAB':
      return 0x09;
    case 'CAPSLOCK':
      return 0x14;
    default:
      // Single letters A–Z map directly to their VK codes.
      if (name.length == 1) {
        final code = name.toUpperCase().codeUnitAt(0);
        if (code >= 0x41 && code <= 0x5A) return code;
      }
      return 0;
  }
}
