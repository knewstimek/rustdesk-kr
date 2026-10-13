import 'android_soft_keyboard_input.dart';

class AndroidSoftKeyboardDispatch {
  Future<void> _pending = Future<void>.value();

  Future<void> send(
    AndroidKeyboardEdit edit, {
    required Future<void> Function() backspace,
    required Future<void> Function(String) insert,
    required void Function(Object) onError,
  }) {
    // Bridge calls may run on different workers; serialize whole text edits.
    _pending = _pending
        .then<void>((_) async {
          for (var i = 0; i < edit.backspaces; ++i) {
            await backspace();
          }
          if (edit.insert.isNotEmpty) await insert(edit.insert);
        })
        .catchError(onError);
    return _pending;
  }
}
