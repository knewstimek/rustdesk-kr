# RustDesk KR

An independent Android build of [RustDesk](https://github.com/rustdesk/rustdesk), focused on Korean text input when controlling a Windows computer. This is not an official RustDesk release.

Based on upstream commit `001b0e96173cea4e49f9f7a67bea95a177dd1de3`. Upstream license notices and source files are retained; see [LICENSE](LICENSE).

## Android input changes

- Send committed Hangul syllables instead of dropping same-length IME updates.
- Observe composition-only changes so the last syllable can be committed without an extra keystroke.
- Treat user-entered digits as content, separately from the hidden input padding.
- Compare whole grapheme clusters so emoji and combining characters are not split.
- Finish composition and reset the local buffer before pointer interaction with the remote view or when the keyboard loses focus.
- Send corrective Backspace events without inheriting toolbar modifiers.

These changes apply to the Android controller → Windows path. Other input paths retain the upstream implementation.

## Installation and verification

The Android package ID is `com.carriez.flutter_hbb.kr`, with the launcher name **RustDesk KR**, allowing installation alongside the official app. APK releases use a dedicated signing key.

The KR Android workflow runs the input regression tests, builds native libraries and APKs from source, signs them, and checks that the x86_64 APK starts on an Android emulator.

Run input regression tests from `flutter/`:

```sh
flutter test test/android_soft_keyboard_input_test.dart
```

## Known limits

- The current composing syllable appears remotely after the IME commits it. Pending composition is not streamed as remote preedit.
- The remote protocol does not expose editor contents or caret state. Focus changes made on the remote computer without client interaction cannot be synchronized automatically.
- Editors differ in how Backspace handles complex emoji. Grapheme edit tests do not establish identical behavior in every Windows editor.
- Automated tests and emulator startup checks do not replace testing Samsung Keyboard and Gboard against a live Windows session.

Local profiles, signing keys, SDKs, build logs, and generated APKs are excluded from Git. Public releases should state the actual verification performed.
