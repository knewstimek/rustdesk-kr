import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';

Widget withAndroidSoftKeyboardBackspace(Widget child) => Shortcuts(
  shortcuts: const <ShortcutActivator, Intent>{
    SingleActivator(LogicalKeyboardKey.backspace): DeleteCharacterIntent(
      forward: false,
    ),
  },
  child: child,
);
