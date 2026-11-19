#!/usr/bin/env bash
set -u
pkg=com.docscan.docscanner
old=old/build/app/outputs/flutter-apk/app-release.apk
new=new/build/app/outputs/flutter-apk/app-release.apk
launch() {
  adb logcat -c
  adb shell monkey -p "$pkg" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
  sleep 30
  pid="$(adb shell pidof "$pkg" | tr -d '\r')"
  if [ -n "$pid" ]; then echo "RESULT $1: running (pid $pid)"; else echo "RESULT $1: NOT running"; fi
  adb logcat -d | grep -E "FATAL EXCEPTION|E AndroidRuntime|Abort message|Fatal signal|E flutter|Caused by" | head -60
}
adb install -r "$old" | tail -1
launch old
adb shell am force-stop "$pkg"
adb install -r "$new" | tail -1
launch upgraded-new
adb shell am force-stop "$pkg"
launch upgraded-new-second-start
exit 0
