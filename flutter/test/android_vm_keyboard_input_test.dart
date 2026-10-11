import 'package:flutter_test/flutter_test.dart';

import '../lib/models/android_soft_keyboard_input.dart';
import '../lib/models/android_vm_keyboard_input.dart';

void main() {
  test(
    'VM input sends digit and letter HID keys instead of Unicode scan values',
    () {
      final keys = androidVmKeyboardEdit(
        const AndroidKeyboardEdit(insert: '12345 abc'),
      );
      expect(keys.where((key) => key.down).map((key) => key.usbHid), [
        0x1e,
        0x1f,
        0x20,
        0x21,
        0x22,
        0x2c,
        0x04,
        0x05,
        0x06,
      ]);
      expect(keys.where((key) => key.text.isNotEmpty), isEmpty);
      final shifted = androidVmKeyboardEdit(
        const AndroidKeyboardEdit(insert: 'A!'),
      );
      expect(shifted.map((key) => [key.usbHid, key.down]), [
        [0xe1, true],
        [0x04, true],
        [0x04, false],
        [0xe1, false],
        [0xe1, true],
        [0x1e, true],
        [0x1e, false],
        [0xe1, false],
      ]);
    },
  );

  test(
    'Hangul uses two-set keys and commits each remote grapheme for deletion',
    () {
      final keys = androidVmKeyboardEdit(
        const AndroidKeyboardEdit(insert: '가나다'),
      );
      expect(keys.where((key) => key.down).map((key) => key.usbHid), [
        0x15,
        0x0e,
        0xe6,
        0xe6,
        0x16,
        0x0e,
        0xe6,
        0xe6,
        0x08,
        0x0e,
        0xe6,
        0xe6,
      ]);
      expect(keys.where((key) => key.text.isNotEmpty), isEmpty);
      final input = AndroidSoftKeyboardInput(padding: '1111');
      input.update('1111ㄱ');
      final replacement = androidVmKeyboardEdit(input.update('1111가'));
      expect(replacement.take(2).map((key) => [key.usbHid, key.down]), [
        [0x2a, true],
        [0x2a, false],
      ]);
      input.update('1111가나다');
      expect(
        androidVmKeyboardEdit(input.update('1111가나'))
            .map((key) => [key.usbHid, key.down]),
        [
          [0x2a, true],
          [0x2a, false],
        ],
      );
    },
  );
}
