# Optional ARM64 native library import (user-provided archive)

The core DocScanner engine remains independent: CMake builds `libds_pagescanner.so`, and the Gradle OpenCV 4.10.0 dependency remains intact. Imported CamScanner binaries are **not enabled by default**.

## Verified source

The uploaded `base.zip` contains all seven requested AArch64 Android (API 21+) ELF binaries:
`libpagescanner.so`, `libscannercs.so`, `libopencv.so`,
`libimageprocessor.so`, `libmagicenhancer.so`,
`libenhance4draft.so`, `liboctopus_classifier.so`.

Four more non-system dependencies are required:
`libMNN.so`, `libncnn.so`, `libCVNN.so`, `libmainstone.so`.
All eleven are included in the user-provided archive, totalling about 40.8 MiB before compression.
The Android NDK/OS supplies the system dependencies `libandroid.so`,
`libc.so`, `libdl.so`, `libjnigraphics.so`, `liblog.so`,
`libm.so` and `libz.so`.

## Prepare locally

1. Obtain the archive **from a source you are authorized to use**.
2. In the repository root, run:
   ```sh
   python tools/prepare_camscanner_native.py /path/to/base.zip
   ```
3. The script validates the 64-bit ARM ELF headers and extracts exactly
   eleven libraries into
   `third_party/doclens/android/src/main/optionalNativeJniLibs/arm64-v8a/`.
   It writes an SHA-256 manifest next to this directory. Both are Git-ignored.
4. The default build **does not include** these files:
   ```sh
   flutter build apk --release --target-platform android-arm64
   ```
5. To include them in a **local** ARM64 APK:
   ```sh
   ORG_GRADLE_PROJECT_docscannerIncludeImportedNative=true flutter build apk --release --target-platform android-arm64
   ```
   On Windows PowerShell:
   ```powershell
   $env:ORG_GRADLE_PROJECT_docscannerIncludeImportedNative="true"
   flutter build apk --release --target-platform android-arm64
   Remove-Item Env:ORG_GRADLE_PROJECT_docscannerIncludeImportedNative
   ```

## Critical limitations

- This change allows **packaging**, not invoking CamScanner native algorithms.
  The exported JNI symbols expect CamScanner's `com.intsig...` classes
  and exact method signatures, initialization, assets/models and resources.
- An arbitrary `System.loadLibrary()` or copying these `.so` files cannot
  make edge detection, image enhancement, or classification work.
- Loading `libopencv.so` beside the separately supplied OpenCV 4.10.0
  dependency can introduce ABI/symbol conflicts; investigate on real devices.
- Only the ARM64 libraries from the upload were inspected. Do not enable
  on 32-bit-only devices.
- No native class bindings, models, or automated run-time tests are included.
  The default independent DocScanner C++ scanner remains the working fallback.
- Distribution rights for the source archive's proprietary binaries have not
  been established. **Do not commit these binaries or publish APKs containing
  them without appropriate permission.**

Further work requires validating library licenses, JNI signatures, model
dependencies, input/output pixel formats, Android runtime loading, device
stability, and quality tests before enabling any of these algorithms.
