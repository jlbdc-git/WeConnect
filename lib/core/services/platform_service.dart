import 'dart:async';

import 'package:flutter/services.dart';

import '../../core/errors/app_exception.dart';

/// Cross-platform abstraction for platform-specific behavior.
///
/// Windows: installs global WH_KEYBOARD_LL / WH_MOUSE_LL hooks via the
/// C++ runner (ptt_hooks.cpp) so PTT works even when unfocused.
/// Android: no global hooks exist — the UI layer provides a press-and-hold
/// PTT button that calls [setPttPressed] directly.
class PlatformService {
  PlatformService._();

  static const _channel = MethodChannel('weconnect/platform');

  static final _pttController = StreamController<bool>.broadcast();
  static bool _listening = false;

  /// PTT down/up events (Windows hooks). Broadcast; UI/service subscribe.
  static Stream<bool> get pttEvents => _pttController.stream;

  /// Configure the global PTT hook. [vkCode] = Windows virtual-key code
  /// (0 = no keyboard hook). [mouseXButton] 0=none, 4=XB1, 5=XB2, 6=middle.
  static Future<bool> setPttHook({int? vkCode, int mouseXButton = 0}) async {
    try {
      final ok = await _channel.invokeMethod<bool>('setPttHook', {
        'vkCode': vkCode ?? 0,
        'mouseXButton': mouseXButton,
      });
      _ensureListener();
      return ok ?? false;
    } on MissingPluginException {
      // Running somewhere without the native runner (e.g. Android) — PTT
      // is handled by the on-screen button there.
      return false;
    } on PlatformException catch (e) {
      throw AppException('ptt_hook_failed',
          message: 'Failed to register PTT key: ${e.message}');
    }
  }

  static Future<void> clearPttHook() async {
    try {
      await _channel.invokeMethod<void>('clearPttHook');
    } on MissingPluginException {
      // no-op off Windows
    }
  }

  /// Enable/disable event gating (only while in a voice channel).
  static Future<void> setPttEnabled(bool enabled) async {
    try {
      await _channel.invokeMethod<void>('setPttEnabled', {'enabled': enabled});
    } on MissingPluginException {
      // no-op off Windows
    }
  }

  static void _ensureListener() {
    if (_listening) return;
    _listening = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onPttEvent') {
        final args = call.arguments as Map?;
        if (args?['type'] == 'ptt') {
          _pttController.add(args?['down'] == true);
        }
      }
      return null;
    });
  }
}
