#!/usr/bin/env bash
set -euo pipefail

APK_PATH=$1
APP_ID=com.carriez.flutter_hbb.kr
ACTIVITY=com.carriez.flutter_hbb.MainActivity

adb logcat -b crash -c
adb install -r "$APK_PATH" >/dev/null
adb shell am start -W -n "$APP_ID/$ACTIVITY" >/dev/null
sleep 10
APP_PID=$(adb shell pidof "$APP_ID" | tr -d '\r')
if [ -z "$APP_PID" ]; then
  echo "FAIL: RustDesk KR process did not remain running"
  adb logcat -d -b crash -t 80
  exit 1
fi
CRASH_COUNT=$(adb logcat -d -b crash | grep -c 'FATAL EXCEPTION' || true)
if [ "$CRASH_COUNT" != 0 ]; then
  echo "FAIL: crash buffer contains $CRASH_COUNT fatal exception(s)"
  adb logcat -d -b crash -t 80
  exit 1
fi
echo "PASS: signed RustDesk KR APK installed and launched without a fatal exception"
