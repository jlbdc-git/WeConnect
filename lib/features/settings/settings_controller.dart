import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/user_settings.dart';
import '../../core/services/platform_service.dart';
import '../../core/state/providers.dart';
import '../voice/voice_controller.dart';

/// Loads and persists user settings (local + remote), and keeps the
/// platform PTT hook in sync with the current settings.
class SettingsController extends AsyncNotifier<UserSettings> {
  StreamSubscription<bool>? _pttSub;

  @override
  Future<UserSettings> build() async {
    final settings = await ref.read(settingsRepositoryProvider).syncFromRemote();

    // Keep the native hook (Windows) in sync.
    await _applyPttHook(settings);
    ref.onDispose(() {
      _pttSub?.cancel();
      PlatformService.clearPttHook();
    });

    return settings;
  }

  Future<void> _applyPttHook(UserSettings s) async {
    if (s.voiceMode == VoiceMode.pushToTalk) {
      final vk = pttKeyNameToVk(s.pttKey);
      final ok = await PlatformService.setPttHook(
        vkCode: vk,
        mouseXButton: s.pttMouseButton,
      );
      if (ok) {
        await _pttSub?.cancel();
        _pttSub = PlatformService.pttEvents.listen((down) {
          ref.read(voiceControllerProvider.notifier).setPttPressed(down);
        });
      }
    } else {
      await PlatformService.clearPttHook();
      await _pttSub?.cancel();
      _pttSub = null;
    }
  }

  /// Persist new settings and apply them everywhere (hook + live voice).
  Future<void> save(UserSettings next) async {
    state = AsyncData(next);
    await ref.read(settingsRepositoryProvider).save(next);
    await _applyPttHook(next);
    // Apply live to an active voice session.
    ref.read(voiceControllerProvider.notifier).applySettings(next);
  }

  Future<void> setVoiceMode(VoiceMode mode) async {
    final current = state.valueOrNull ?? const UserSettings();
    await save(current.copyWith(voiceMode: mode));
  }
}

final settingsControllerProvider =
    AsyncNotifierProvider<SettingsController, UserSettings>(
        SettingsController.new);
