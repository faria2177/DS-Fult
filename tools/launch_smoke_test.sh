#!/usr/bin/env bash
# Opens the freshly built app on an emulator and fails the build when the
# app does not start cleanly. Catches problems that unit tests cannot see:
# release shrinking (R8), plugin/JNI breakage after a dependency update,
# and crashes during start-up (v0.5.55/0.5.56 never opened).
set -u
pkg=com.docscan.docscanner
apk="${1:-build/app/outputs/flutter-apk/app-release.apk}"
mkdir -p launch-logs
adb install -r "$apk" | tail -1
adb logcat -c
adb shell monkey -p "$pkg" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
sleep 35
adb logcat -d > launch-logs/logcat.txt
adb shell screencap -p /sdcard/launch.png && adb pull /sdcard/launch.png launch-logs/launch.png >/dev/null 2>&1
pid="$(adb shell pidof "$pkg" | tr -d '\r')"
problems="$(grep -E "FATAL EXCEPTION|Fatal signal|E flutter :|Unhandled Exception|ComponentDiscovery.*NoSuchMethodException" launch-logs/logcat.txt | grep -v "Could not prepare segmentation model" | head -40)"
if [ -z "$pid" ]; then
  echo "::error::DocScanner is not running 35 s after launch"
  grep -E "AndroidRuntime|Fatal signal|E flutter|Caused by" launch-logs/logcat.txt | head -60
  exit 1
fi
if [ -n "$problems" ]; then
  echo "::error::DocScanner logged errors while starting"
  echo "$problems"
  exit 1
fi
echo "DocScanner started cleanly (pid $pid)."
