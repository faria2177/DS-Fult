#!/usr/bin/env bash
set -u
pkg=com.docscan.docscanner
for apk in $(find apks -name '*.apk' | sort -r); do
  echo "=== $apk"
  adb uninstall "$pkg" >/dev/null 2>&1 || true
  adb install -r "$apk" 2>&1 | tail -1
  adb logcat -c
  adb shell monkey -p "$pkg" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
  sleep 40
  pid="$(adb shell pidof "$pkg" | tr -d '\r')"
  if [ -n "$pid" ]; then echo "RESULT: running (pid $pid)"; else echo "RESULT: NOT running"; fi
  adb logcat -d | grep -E "FATAL EXCEPTION|E AndroidRuntime|Abort message|Fatal signal|E flutter|Caused by|#[0-9][0-9] pc|docscan" | grep -v "^.* I ActivityTaskManager" | head -80
done
exit 0
