#!/usr/bin/env bash
# Installs each downloaded release APK on the emulator, opens it and records
# whether the app process survives, plus the crash log if it does not.
set -u
mkdir -p launch-logs
pkg=com.docscan.docscanner
for tag in $TAGS_TO_TEST; do
  apk="$(find "apks/$tag" -name '*.apk' | head -1)"
  [ -n "$apk" ] || continue
  echo "=== $tag ($apk)"
  adb uninstall "$pkg" >/dev/null 2>&1 || true
  adb install -r "$apk" > "launch-logs/$tag-install.txt" 2>&1
  cat "launch-logs/$tag-install.txt"
  adb logcat -c
  adb shell monkey -p "$pkg" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
  sleep 25
  adb shell screencap -p /sdcard/shot.png && adb pull /sdcard/shot.png "launch-logs/$tag.png" >/dev/null 2>&1
  pid="$(adb shell pidof "$pkg" | tr -d '\r')"
  adb logcat -d > "launch-logs/$tag-logcat.txt"
  if [ -n "$pid" ]; then
    echo "RESULT $tag: running (pid $pid)"
  else
    echo "RESULT $tag: NOT running"
  fi
  grep -E "FATAL EXCEPTION|AndroidRuntime|Abort message|signal 6|signal 11|E/flutter|libc  |DEBUG   :|UnsatisfiedLink|ClassNotFound|NoSuchMethod" \
    "launch-logs/$tag-logcat.txt" | head -60
done
exit 0
