#!/usr/bin/env bash
set -euo pipefail

# flutter_tesseract_ocr 0.4.31 still publishes an old Gradle buildscript
# containing jcenter(), which Gradle 9 does not support. The host app already
# configures the Android Gradle Plugin, so the redundant plugin buildscript can
# be removed without changing or redistributing the package's native binaries.
task_pub_cache="${PUB_CACHE:-${HOME}/.pub-cache}"
plugin_gradle="$task_pub_cache/hosted/pub.dev/flutter_tesseract_ocr-0.4.31/android/build.gradle"
if [ ! -f "$plugin_gradle" ]; then
  printf 'Missing expected plugin Gradle file: %s\n' "$plugin_gradle" >&2
  exit 1
fi

sed -i '/^buildscript {/,/^}/d' "$plugin_gradle"
sed -i 's/jcenter()/mavenCentral()/g' "$plugin_gradle"
printf 'Patched legacy Tesseract Gradle repositories.\n'
