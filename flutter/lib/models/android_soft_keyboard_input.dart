import 'package:characters/characters.dart';

class AndroidKeyboardEdit {
  final int backspaces;
  final String insert;

  const AndroidKeyboardEdit({this.backspaces = 0, this.insert = ''});
}

/// Tracks text shown remotely, including the current composing syllable.
class AndroidSoftKeyboardInput {
  final String padding;
  int _paddingLength = 0;
  String _sentText = '';
  String _pending = '';

  AndroidSoftKeyboardInput({required this.padding}) {
    reset();
  }

  void reset() {
    _paddingLength = padding.length;
    _sentText = '';
    _pending = '';
  }

  AndroidKeyboardEdit update(String text,
      {int composingStart = -1, int composingEnd = -1}) {
    var paddingBackspaces = 0;
    if (_paddingLength > 0 &&
        !text.startsWith(padding.substring(0, _paddingLength))) {
      if (text.length < _paddingLength &&
          text == padding.substring(0, text.length)) {
        // Padding is a Backspace reservoir, not actual remote text.
        paddingBackspaces = 1;
        _paddingLength = text.length;
      } else {
        // A paste can replace the hidden field, but must not erase remote text.
        _paddingLength = 0;
        _sentText = '';
      }
    }

    _pending = text.substring(_paddingLength);
    // Render composing text too; waiting for commit hides the final syllable.
    final edit = _diff(_pending);
    return AndroidKeyboardEdit(
        backspaces: edit.backspaces + paddingBackspaces, insert: edit.insert);
  }

  AndroidKeyboardEdit finish() => _diff(_pending);

  AndroidKeyboardEdit _diff(String next) {
    final oldCharacters = _sentText.characters.toList(growable: false);
    final newCharacters = next.characters.toList(growable: false);
    var common = 0;
    while (common < oldCharacters.length &&
        common < newCharacters.length &&
        oldCharacters[common] == newCharacters[common]) {
      ++common;
    }
    _sentText = next;
    return AndroidKeyboardEdit(
        backspaces: oldCharacters.length - common,
        insert: newCharacters.skip(common).join());
  }
}
