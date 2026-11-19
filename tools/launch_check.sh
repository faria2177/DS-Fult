#!/usr/bin/env bash
# Installs $APK on the emulator, opens it and records whether the app
# process survives, plus the crash log if it does not.
set -u
mkdir -p launch-logs
pkg=com.docscan.docscanner
tag="$(echo "${TAG:-app}" | tr '/+' '__')"
echo "=== $tag ($APK)"
adb install -r "$APK" 2>&1 | tail -2
adb logcat -c
adb shell monkey -p "$pkg" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
sleep 30
adb shell screencap -p /sdcard/shot.png && adb pull /sdcard/shot.png "launch-logs/$tag.png" >/dev/null 2>&1
pid="$(adb shell pidof "$pkg" | tr -d '\r')"
adb logcat -d > "launch-logs/$tag-logcat.txt"
if [ -n "$pid" ]; then echo "RESULT $tag: running (pid $pid)"; else echo "RESULT $tag: NOT running"; fi
grep -E "FATAL EXCEPTION|E AndroidRuntime|Abort message|Fatal signal|E flutter|E/flutter|Caused by|at com\.|at io\.|at android\.|backtrace|#0[0-9] pc" \
  "launch-logs/$tag-logcat.txt" | head -80
exit 0
