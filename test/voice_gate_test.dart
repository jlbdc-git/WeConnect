import 'package:flutter_test/flutter_test.dart';
import 'package:we_connect/core/services/voice_gate.dart';

/// Records every `enabled` transition so tests can assert the gate's
/// effect on the "transmitter".
class FakeTrack implements GateTrack {
  bool _enabled = true;

  @override
  bool get enabled => _enabled;

  @override
  set enabled(bool value) => _enabled = value;
}

void main() {
  group('VoiceGate — PTT mode', () {
    late FakeTrack track;
    late VoiceGate gate;

    setUp(() {
      track = FakeTrack();
      gate = VoiceGate();
      gate.configure(pttMode: true, vadSensitivity: 50);
    });

    test('starts closed in PTT mode', () async {
      await gate.attach(track);
      expect(track.enabled, isFalse,
          reason: 'PTT must not transmit before a press');
    });

    test('opens while pressed, closes on release', () async {
      await gate.attach(track);

      gate.setPttPressed(true);
      expect(track.enabled, isTrue, reason: 'press → transmit');
      expect(gate.speaking, isTrue);

      gate.setPttPressed(false);
      expect(track.enabled, isFalse, reason: 'release → stop transmit');
      expect(gate.speaking, isFalse);
    });

    test('mute overrides an active PTT press', () async {
      await gate.attach(track);

      gate.setPttPressed(true);
      expect(track.enabled, isTrue);

      gate.setMuted(true);
      expect(track.enabled, isFalse,
          reason: 'muted means NEVER transmit, even pressed');
      expect(gate.speaking, isFalse);

      gate.setMuted(false);
      expect(track.enabled, isTrue,
          reason: 'unmuting restores the still-held press');
    });

    test('reports speaking transitions via callback', () async {
      final events = <bool>[];
      final g = VoiceGate(onSpeakingChanged: events.add)
        ..configure(pttMode: true, vadSensitivity: 50);
      await g.attach(track);

      g.setPttPressed(true);
      g.setPttPressed(false);
      expect(events, [true, false]);
    });
  });

  group('VoiceGate — VAD mode', () {
    late FakeTrack track;
    late VoiceGate gate;

    setUp(() {
      track = FakeTrack();
      gate = VoiceGate();
      gate.configure(pttMode: false, vadSensitivity: 50);
    });

    test('track stays open (DTX handles silence)', () async {
      await gate.attach(track);
      expect(track.enabled, isTrue);
    });

    test('external speaking pulses drive the indicator with hold-open',
        () async {
      final events = <bool>[];
      final g = VoiceGate(onSpeakingChanged: events.add)
        ..configure(pttMode: false, vadSensitivity: 0);
      await g.attach(track);

      g.setExternalSpeaking(true);
      expect(g.speaking, isTrue);

      g.setExternalSpeaking(false);
      // Hold-open window (150ms at sensitivity 0) keeps it "speaking".
      expect(g.speaking, isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 220));
      expect(g.speaking, isFalse,
          reason: 'indicator clears after the hold-open window');
    });

    test('mode switch back to PTT re-gates the track', () async {
      await gate.attach(track);
      gate.setPttPressed(false); // "released"

      gate.configure(pttMode: true, vadSensitivity: 50);
      gate.refreshMode();
      expect(track.enabled, isFalse,
          reason: 'switching to PTT with button up must close the gate');
    });
  });

  group('VoiceGate — lifecycle', () {
    test('detach closes everything and stops reporting', () async {
      final events = <bool>[];
      final track = FakeTrack();
      final gate = VoiceGate(onSpeakingChanged: events.add)
        ..configure(pttMode: true, vadSensitivity: 50);
      await gate.attach(track);

      gate.setPttPressed(true);
      gate.dispose();
      expect(events, [true]);
    });
  });
}
