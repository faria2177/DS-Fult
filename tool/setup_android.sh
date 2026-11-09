#!/usr/bin/env bash
set -euo pipefail

# Flutter's official template supplies matching Gradle wrapper/AGP versions.
# It is generated at build time so this repository stays upgradable and does
# not ship an unverified hand-written Android template.
flutter create --platforms=android --project-name=docscanner --org=com.docscan .

# The template defaults to the much larger Gradle "all" distribution via a
# service URL that currently redirects to GitHub release assets. CI downloads
# intermittently fail with HTTP 504 there. Use Gradle's official direct
# download host and runtime-only "bin" archive instead; the Android build
# does not need the Gradle source/documentation bundle.
wrapper_props='android/gradle/wrapper/gradle-wrapper.properties'
if [ -f "$wrapper_props" ]; then
  sed -i 's#services.gradle.org/distributions/#downloads.gradle.org/distributions/#; s#-all.zip#-bin.zip#' "$wrapper_props"
fi

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
  # Release builds need INTERNET only for user-approved text AI calls.
  # Flutter's debug manifest has this permission; release does not by default.
  if ! grep -q 'android.permission.INTERNET' "$manifest"; then
    sed -i '/<application/i\    <uses-permission android:name="android.permission.INTERNET" />' "$manifest"
  fi
fi

# The ML Kit plugin references optional Asian-script recognizers even when
# this app only requests the bundled Latin model. R8 needs to know these
# optional, unused classes are intentionally absent from the APK.
gradle_file='android/app/build.gradle.kts'
cp tool/mlkit-proguard-rules.pro android/app/proguard-rules.pro
if ! grep -q 'proguardFiles("proguard-rules.pro")' "$gradle_file"; then
  sed -i '/signingConfig = signingConfigs.getByName("debug")/a\            proguardFiles("proguard-rules.pro")' "$gradle_file"
fi
