import 'dart:async';

/// Minimal transport-agnostic view of a mutable audio track.
///
/// The gate only needs to flip `enabled` — the WebRTC contract for
/// "stop capturing/sending frames". Decoupling the gate from the concrete
/// track type keeps it unit-testable and lets the same gate serve any
/// WebRTC implementation.
abstract class GateTrack {
  bool get enabled;
  set enabled(bool value);
}

/// Gate between the microphone and WebRTC — the abstraction that lets
/// Voice Activity (VAD) and Push-to-Talk (PTT) share ONE audio pipeline.
///
///              ┌────────────┐
///  mic track → │  Gate      │ → published track (enabled/disabled)
///              │ (VAD/PTT)  │
///              └────────────┘
///
/// PTT mode : track.enabled is toggled by setPttPressed() — hard gating.
/// VAD mode : the track stays open and Opus DTX (enabled at publish time)
///            suppresses silence packets at the codec level; the *speaking
///            indicator* is fed externally from LiveKit's server-side
///            active-speaker detection (real VAD on the published stream).
///            This mirrors how Discord's "voice activity" behaves.
///
/// Mute overrides everything: the gate stays closed.
class VoiceGate {
  VoiceGate({this.onSpeakingChanged});

  /// Whether the user is actively transmitting (UI speaking indicator).
  final void Function(bool speaking)? onSpeakingChanged;

  // --- config ---
  bool _modeIsPtt = false;
  int _vadSensitivity = 50; // 0..100 → hold-open window
  bool _muted = false;

  // --- speaking state ---
  bool _speaking = false;
  Timer? _holdTimer;

  // --- PTT state ---
  bool _pttPressed = false;

  /// The LOCAL mic track whose `enabled` flag we toggle.
  GateTrack? _track;

  bool get speaking => _speaking;
  bool get muted => _muted;
  bool get modeIsPtt => _modeIsPtt;
  bool get isOpen {
    final t = _track;
    return t != null && t.enabled;
  }

  void configure({required bool pttMode, required int vadSensitivity}) {
    _modeIsPtt = pttMode;
    _vadSensitivity = vadSensitivity;
  }

  /// Attach the local mic track. Detach (null) on leave/dispose.
  Future<void> attach(GateTrack? track) async {
    _track = track;
    _apply();
  }

  void setMuted(bool value) {
    _muted = value;
    if (value) _setSpeaking(false);
    _apply();
  }

  void setPttPressed(bool pressed) {
    _pttPressed = pressed;
    if (_modeIsPtt) {
      _setSpeaking(pressed && !_muted);
    }
    _apply();
  }

  /// VAD mode: speaking state comes from LiveKit active-speaker events
  /// (server-side analysis of the real published audio).
  void setExternalSpeaking(bool value) {
    if (_modeIsPtt) return;
    if (value) {
      _holdTimer?.cancel();
      _setSpeaking(!_muted);
    } else {
      // hold-open window scales with sensitivity (snappier at low end).
      final ms = 150 + _vadSensitivity * 8; // 150..950 ms
      _holdTimer?.cancel();
      _holdTimer = Timer(Duration(milliseconds: ms), () {
        _setSpeaking(false);
      });
    }
  }

  /// Re-evaluate after mode/threshold changes.
  void refreshMode() => _apply();

  void _apply() {
    final track = _track;
    if (track == null) return;
    final open = !_muted && (_modeIsPtt ? _pttPressed : true);
    // `enabled = false` is a real media gate: no frames are captured or sent.
    track.enabled = open;
  }

  void _setSpeaking(bool value) {
    if (_speaking == value) return;
    _speaking = value;
    onSpeakingChanged?.call(value);
  }

  void dispose() {
    _holdTimer?.cancel();
    _track = null;
  }
}
