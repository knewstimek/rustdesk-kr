import 'package:characters/characters.dart';

import 'android_soft_keyboard_input.dart';

class AndroidVmKey {
  final int usbHid;
  final bool down;
  final String text;

  const AndroidVmKey(this.usbHid, this.down) : text = '';
  const AndroidVmKey.text(this.text) : usbHid = 0, down = false;
}

const _initial = [
  'r',
  'R',
  's',
  'e',
  'E',
  'f',
  'a',
  'q',
  'Q',
  't',
  'T',
  'd',
  'w',
  'W',
  'c',
  'z',
  'x',
  'v',
  'g',
];
const _vowel = [
  'k',
  'o',
  'i',
  'O',
  'j',
  'p',
  'u',
  'P',
  'h',
  'hk',
  'ho',
  'hl',
  'y',
  'n',
  'nj',
  'np',
  'nl',
  'b',
  'm',
  'ml',
  'l',
];
const _final = [
  '',
  'r',
  'R',
  'rt',
  's',
  'sw',
  'sg',
  'e',
  'f',
  'fr',
  'fa',
  'fq',
  'ft',
  'fx',
  'fv',
  'fg',
  'a',
  'q',
  'qt',
  't',
  'T',
  'd',
  'w',
  'c',
  'z',
  'x',
  'v',
  'g',
];
const _consonant = [
  'r',
  'R',
  'rt',
  's',
  'sw',
  'sg',
  'e',
  'E',
  'f',
  'fr',
  'fa',
  'fq',
  'ft',
  'fx',
  'fv',
  'fg',
  'a',
  'q',
  'Q',
  'qt',
  't',
  'T',
  'd',
  'w',
  'W',
  'c',
  'z',
  'x',
  'v',
  'g',
];

String? _hangulKeys(String character) {
  if (character.runes.length != 1) return null;
  final code = character.runes.first;
  if (code >= 0xac00 && code <= 0xd7a3) {
    final syllable = code - 0xac00;
    return _initial[syllable ~/ 588] +
        _vowel[(syllable % 588) ~/ 28] +
        _final[syllable % 28];
  }
  if (code >= 0x3131 && code <= 0x314e) return _consonant[code - 0x3131];
  if (code >= 0x314f && code <= 0x3163) return _vowel[code - 0x314f];
  return null;
}

List<AndroidVmKey>? _asciiKeys(String character) {
  if (character.length != 1) return null;
  final code = character.toLowerCase().codeUnitAt(0);
  if (code >= 97 && code <= 122) {
    final key = 0x04 + code - 97;
    final shifted = character != character.toLowerCase();
    return [
      if (shifted) const AndroidVmKey(0xe1, true),
      AndroidVmKey(key, true),
      AndroidVmKey(key, false),
      if (shifted) const AndroidVmKey(0xe1, false),
    ];
  }
  const plain = "1234567890-=[]\\;'\x60,./";
  const shifted = '!@#\$%^&*()_+{}|:"~<>?';
  const codes = [
    0x1e,
    0x1f,
    0x20,
    0x21,
    0x22,
    0x23,
    0x24,
    0x25,
    0x26,
    0x27,
    0x2d,
    0x2e,
    0x2f,
    0x30,
    0x31,
    0x33,
    0x34,
    0x35,
    0x36,
    0x37,
    0x38,
  ];
  final shiftIndex = shifted.indexOf(character);
  final index = plain.indexOf(character);
  final control = {'\n': 0x28, '\t': 0x2b, ' ': 0x2c}[character];
  final key =
      control ??
      (index >= 0
          ? codes[index]
          : shiftIndex >= 0
          ? codes[shiftIndex]
          : null);
  if (key == null) return null;
  return [
    if (shiftIndex >= 0) const AndroidVmKey(0xe1, true),
    AndroidVmKey(key, true),
    AndroidVmKey(key, false),
    if (shiftIndex >= 0) const AndroidVmKey(0xe1, false),
  ];
}

enum AndroidVmImeKey { type1, type2, type3, dedicated }

extension AndroidVmImeKeyLabel on AndroidVmImeKey {
  String get label => const ['101-1', '101-2', '101-3', '103/106'][index];
  String get shortcut =>
      const ['Right Alt', 'Right Ctrl', 'Shift+Space', '한/영'][index];
}

List<AndroidVmKey> androidVmImeToggle(AndroidVmImeKey choice) {
  if (choice == AndroidVmImeKey.type3) {
    return const [
      AndroidVmKey(0xe1, true),
      AndroidVmKey(0x2c, true),
      AndroidVmKey(0x2c, false),
      AndroidVmKey(0xe1, false),
    ];
  }
  final hid = choice == AndroidVmImeKey.type1
      ? 0xe6
      : choice == AndroidVmImeKey.type2
      ? 0xe4
      : 0x90;
  return [AndroidVmKey(hid, true), AndroidVmKey(hid, false)];
}

String? androidVmKeyboardPacket(List<AndroidVmKey> keys) {
  if (keys.any((key) => key.text.isNotEmpty)) return null;
  return 'vm_keys:' +
      String.fromCharCodes(
        keys.map((key) => key.usbHid | (key.down ? 0x100 : 0)),
      );
}

List<AndroidVmKey> androidVmKeyboardEdit(AndroidKeyboardEdit edit) {
  final keys = <AndroidVmKey>[];
  for (var i = 0; i < edit.backspaces; ++i) {
    keys.addAll(const [AndroidVmKey(0x2a, true), AndroidVmKey(0x2a, false)]);
  }
  for (final character in edit.insert.characters) {
    final hangul = _hangulKeys(character);
    if (hangul != null) {
      for (final key in hangul.split('')) {
        keys.addAll(_asciiKeys(key)!);
      }
      // Space commits Korean composition; remove only that added space.
      keys.addAll(const [
        AndroidVmKey(0x2c, true),
        AndroidVmKey(0x2c, false),
        AndroidVmKey(0x2a, true),
        AndroidVmKey(0x2a, false),
      ]);
    } else {
      keys.addAll(_asciiKeys(character) ?? [AndroidVmKey.text(character)]);
    }
  }
  return keys;
}
