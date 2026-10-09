import 'package:flutter_test/flutter_test.dart';
import 'package:characters/characters.dart';
import '../lib/models/android_soft_keyboard_input.dart';

const padding = '11111111';

String apply(String remote, AndroidKeyboardEdit edit) {
  final characters = remote.characters.toList();
  final keep = characters.length - edit.backspaces;
  return characters.take(keep < 0 ? 0 : keep).join() + edit.insert;
}

void main() {
  test('Hangul composition commits complete syllables, including end-only events',
      () {
    final input = AndroidSoftKeyboardInput(padding: padding);
    var remote = '';
    final values = ['ㄱ', '가', '가ㄴ', '가나', '가나ㄷ', '가나다'];
    final starts = [0, 0, 1, 1, 2, 2];
    for (var i = 0; i < values.length; ++i) {
      final edit = input.update(padding + values[i],
          composingStart: padding.length + starts[i],
          composingEnd: padding.length + values[i].length);
      expect(edit.backspaces, 0);
      remote = apply(remote, edit);
    }
    expect(remote, '가나');
    remote = apply(remote, input.update(padding + '가나다'));
    expect(remote, '가나다');
    expect(input.finish().insert, '');

    input.reset();
    remote = '';
    for (final value in ['ㅇ', '아', '안', '안ㄴ', '안녀', '안녕']) {
      final start = value.length == 1 ? 0 : 1;
      remote = apply(remote, input.update(padding + value,
          composingStart: padding.length + start,
          composingEnd: padding.length + value.length));
    }
    remote = apply(remote, input.finish());
    expect(remote, '안녕');
  });

  test('Literal 1 is content, and Unicode replacement keeps whole characters',
      () {
    final input = AndroidSoftKeyboardInput(padding: padding);
    var remote = apply('', input.update(padding + 'abc1'));
    remote = apply(remote, input.update(padding + 'xyz1'));
    expect(remote, 'xyz1');
    input.reset();
    remote = apply('', input.update(padding + '😀'));
    final edit = input.update(padding + '😃');
    expect(edit.backspaces, 1);
    expect(edit.insert, '😃');
    remote = apply(remote, edit);
    expect(remote, '😃');

    input.reset();
    input.update(padding + '👩‍💻');
    final joined = input.update(padding + '👩‍🔬');
    expect(joined.backspaces, 1);
    expect(joined.insert, '👩‍🔬');

    input.reset();
    input.update(padding + 'e\u0301');
    final combining = input.update(padding + 'a\u0301');
    expect(combining.backspaces, 1);
    expect(combining.insert, 'a\u0301');

    input.reset();
    final pasted = input.update('1한글😀');
    expect(pasted.backspaces, 0);
    expect(pasted.insert, '1한글😀');
  });

  test('Target reset forgets old text; deletion and recomposition stay local',
      () {
    final input = AndroidSoftKeyboardInput(padding: padding);
    input.update(padding + '이전');
    input.reset();
    final target = input.update(padding + '새창');
    expect(target.backspaces, 0);
    expect(target.insert, '새창');

    input.reset();
    input.update(padding + '간');
    final pending = input.update(padding + '가',
        composingStart: padding.length, composingEnd: padding.length + 1);
    expect(pending.backspaces, 0);
    expect(pending.insert, '');
    final committed = input.finish();
    expect(committed.backspaces, 1);
    expect(committed.insert, '가');

    input.reset();
    input.update(padding + '가나다');
    expect(input.update(padding).backspaces, 3);
    expect(input.update(padding.substring(1)).backspaces, 1);
    expect(input.update(padding).insert, '1');
  });
}
