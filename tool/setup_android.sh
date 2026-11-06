#!/usr/bin/env bash
set -euo pipefail

# Flutter's official template supplies matching Gradle wrapper/AGP versions.
# It is generated at build time so this repository stays upgradable and does
# not ship an unverified hand-written Android template.
flutter create --platforms=android --project-name=docscanner --org=com.docscan .

manifest='android/app/src/main/AndroidManifest.xml'
if [ -f "$manifest" ]; then
  sed -i 's/android:label="docscanner"/android:label="DocScanner"/' "$manifest"
fi
