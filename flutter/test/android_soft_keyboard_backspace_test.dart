import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/mobile/widgets/android_soft_keyboard_backspace.dart';
import '../lib/models/android_soft_keyboard_input.dart';

void main() {
  for (final text in ['abc123', '가나다']) {
    testWidgets('Backspace tap and repeat delete remote $text once per event', (
      tester,
    ) async {
      const padding = '11111111';
      final input = AndroidSoftKeyboardInput(padding: padding);
      var remote = input.update(padding + text).insert;
      final controller = TextEditingController.fromValue(
        TextEditingValue(
          text: padding + text,
          selection: TextSelection.collapsed(
            offset: padding.length + text.length,
          ),
        ),
      );
      controller.addListener(() {
        final edit = input.update(controller.text);
        remote =
            remote.substring(0, remote.length - edit.backspaces) + edit.insert;
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Focus(
              onKeyEvent: (_, event) =>
                  event.logicalKey == LogicalKeyboardKey.backspace
                  ? KeyEventResult.skipRemainingHandlers
                  : KeyEventResult.ignored,
              child: withAndroidSoftKeyboardBackspace(
                TextField(autofocus: true, controller: controller),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.backspace);
      expect(remote, text.substring(0, text.length - 1));
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.backspace);
      expect(remote, text.substring(0, text.length - 2));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.backspace);
      expect(remote, text.substring(0, text.length - 2));
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));
  }
}
