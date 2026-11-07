#!/usr/bin/env bash
set -euo pipefail

# Flutter's official template supplies matching Gradle wrapper/AGP versions.
# It is generated at build time so this repository stays upgradable and does
# not ship an unverified hand-written Android template.
flutter create --platforms=android --project-name=docscanner --org=com.docscan .

# Reapply the branded launcher icon every time Flutter regenerates android/.
# Adaptive icons are used on Android 8+, with density-specific PNG fallbacks.
for density in mdpi hdpi xhdpi xxhdpi xxxhdpi; do
  target="android/app/src/main/res/mipmap-$density"
  mkdir -p "$target"
  cp "assets/branding/android/mipmap-$density/ic_launcher.png" "$target/ic_launcher.png"
  cp "assets/branding/android/mipmap-$density/ic_launcher_foreground.png" "$target/ic_launcher_foreground.png"
done
mkdir -p android/app/src/main/res/mipmap-anydpi-v26 android/app/src/main/res/values
cp assets/branding/android/mipmap-anydpi-v26/ic_launcher.xml android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml
cp assets/branding/android/values/ds_launcher_colors.xml android/app/src/main/res/values/ds_launcher_colors.xml

# Several Flutter Android plugins still use the pre-AGP-9 DSL. Keep the
# compatibility switches until those plugins migrate to the new DSL.
printf '\nandroid.newDsl=false\nandroid.builtInKotlin=false\n' >> android/gradle.properties

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
