import 'package:flutter_test/flutter_test.dart';
import 'package:we_connect/features/voice/voice_controller.dart';

void main() {
  group('pttKeyNameToVk', () {
    test('single letters map to their VK codes', () {
      expect(pttKeyNameToVk('V'), 0x56); // 'V'
      expect(pttKeyNameToVk('a'), 0x41); // case-insensitive 'A'
      expect(pttKeyNameToVk('B'), 0x42);
    });

    test('named keys map correctly', () {
      expect(pttKeyNameToVk('Space'), 0x20);
      expect(pttKeyNameToVk('LAlt'), 0xA4);
      expect(pttKeyNameToVk('RAlt'), 0xA5);
      expect(pttKeyNameToVk('LCtrl'), 0xA2);
      expect(pttKeyNameToVk('CapsLock'), 0x14);
      expect(pttKeyNameToVk('Tab'), 0x09);
    });

    test('unknown names return 0 (no keyboard hook)', () {
      expect(pttKeyNameToVk('F13'), 0);
      expect(pttKeyNameToVk(''), 0);
    });
  });
}
