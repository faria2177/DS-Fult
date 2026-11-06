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

# The ML Kit plugin references optional Asian-script recognizers even when
# this app only requests the bundled Latin model. R8 needs to know these
# optional, unused classes are intentionally absent from the APK.
gradle_file='android/app/build.gradle.kts'
cp tool/mlkit-proguard-rules.pro android/app/proguard-rules.pro
if ! grep -q 'proguardFiles("proguard-rules.pro")' "$gradle_file"; then
  sed -i '/signingConfig = signingConfigs.getByName("debug")/a\            proguardFiles("proguard-rules.pro")' "$gradle_file"
fi
