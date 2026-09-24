import 'package:flutter_test/flutter_test.dart';
import 'package:we_connect/core/models/message.dart';
import 'package:we_connect/core/models/profile.dart';
import 'package:we_connect/core/models/user_settings.dart';

void main() {
  group('Profile', () {
    test('parses from database JSON', () {
      final p = Profile.fromJson({
        'id': 'abc-123',
        'username': 'jane_doe',
        'display_name': 'Jane',
        'tag': 4242,
        'avatar_url': null,
      });
      expect(p.id, 'abc-123');
      expect(p.username, 'jane_doe');
      expect(p.tag, 4242);
      expect(p.effectiveName, 'Jane');
    });

    test('falls back to username when display name empty', () {
      final p = Profile(
        id: 'x',
        username: 'fallback',
        displayName: '',
        tag: 1000,
      );
      expect(p.effectiveName, 'fallback');
    });
  });

  group('UserSettings', () {
    test('JSON round-trip preserves values', () {
      const s = UserSettings(
        voiceMode: VoiceMode.pushToTalk,
        pttKey: 'B',
        pttMouseButton: 5,
        noiseSuppression: false,
        autoGainControl: false,
        vadSensitivity: 75,
      );
      final restored = UserSettings.fromDbJson(s.toDbJson());
      expect(restored.voiceMode, VoiceMode.pushToTalk);
      expect(restored.pttKey, 'B');
      expect(restored.pttMouseButton, 5);
      expect(restored.noiseSuppression, isFalse);
      // echoCancellation keeps its default (true) — verifies defaults survive
      // the round-trip even when not overridden in the constructor.
      expect(restored.echoCancellation, isTrue);
      expect(restored.autoGainControl, isFalse);
      expect(restored.vadSensitivity, 75);
    });

    test('defaults are sensible for a new user', () {
      final s = UserSettings.fromDbJson({});
      expect(s.voiceMode, VoiceMode.voiceActivity);
      expect(s.pttKey, 'V');
      expect(s.noiseSuppression, isTrue);
      expect(s.echoCancellation, isTrue);
      expect(s.autoGainControl, isTrue);
      expect(s.vadSensitivity, 50);
    });

    test('copyWith overrides only given fields', () {
      const base = UserSettings();
      final modified = base.copyWith(pttKey: 'Space');
      expect(modified.pttKey, 'Space');
      expect(modified.vadSensitivity, base.vadSensitivity);
    });
  });

  group('Message', () {
    test('parses timestamps as UTC', () {
      final m = Message.fromJson({
        'id': 'm1',
        'channel_id': 'c1',
        'sender_id': 's1',
        'content': 'hello',
        'created_at': '2026-09-24T10:00:00Z',
        'edited_at': null,
      });
      expect(m.content, 'hello');
      expect(m.createdAt.isUtc, isTrue);
      expect(m.editedAt, isNull);
    });

    test('edited messages parse their edited_at', () {
      final m = Message.fromJson({
        'id': 'm1',
        'channel_id': 'c1',
        'sender_id': 's1',
        'content': 'edited',
        'created_at': '2026-09-24T10:00:00Z',
        'edited_at': '2026-09-24T10:05:00Z',
      });
      expect(m.editedAt, isNotNull);
    });
  });
}
