# DocScanner native integration compatibility audit

Source: user-provided `base.zip`, inspected as ARM64 ELF shared objects
with `readelf -d` and exported JNI symbol names with `readelf -Ws`.
This is a static inspection only: it does not establish that calling any
proprietary symbol is safe, licensed, or effective.

## Libraries and non-Android ELF dependencies

| Native library | Additional `.so` dependencies inside supplied bundle | JNI classes observed |
| --- | --- | --- |
| `libpagescanner.so` | `libopencv.so`, `libMNN.so` | `com.intsig.nativelib.PageScanner` |
| `libscannercs.so` | `libmainstone.so` | `com.intsig.scanner.ScannerEngine` |
| `libopencv.so` | None (Android system libraries only) | Internal OpenCV implementation |
| `libimageprocessor.so` | `libopencv.so`, `libncnn.so`, `libMNN.so` | `com.intsig.nativelib.ImageProcessor` |
| `libmagicenhancer.so` | `libopencv.so`, `libncnn.so`, `libMNN.so`, `libCVNN.so` | `com.intsig.nativelib.MagicEnhancer` |
| `libenhance4draft.so` | `libopencv.so`, `libscannercs.so`, `libmainstone.so` | `com.intsig.scanner.Enhance4DraftEngine` |
| `liboctopus_classifier.so` | `libopencv.so`, `libncnn.so`, `libMNN.so` | `com.intsig.nativelib.OctopusClassifier` |

All also depend on one or more ordinary Android system libs
(`libc.so`, `libm.so`, `libdl.so`, `liblog.so`, `libjnigraphics.so`,
`libandroid.so`, `libz.so`). The supplied eleven ELF files cover the
identified non-system direct dependencies. Transitive dependencies, model
assets, licenses, CPU feature compatibility and actual runtime behavior
have **not** been comprehensively established.

## Examples of observed exported JNI entry points

- `PageScanner`: `CropDewarpImagePosFile`, `ContourMaskBitmap`
- `ScannerEngine`: `detectBorder`, `adjustBitmap`
- `ImageProcessor`: `deblurBitmap`, `DewarpImgBitmap`
- `MagicEnhancer`: `deshadowBitmap`, `ImageSilverBulletBitmap`
- `Enhance4DraftEngine`: `enhanceImageS`
- `OctopusClassifier`: `documentRadarBitmap`, `getClarityClassifyBitmap`

**Names alone do not specify Java/Kotlin parameter types, return types,
model initialization, thread safety, image pixel layout or resource ownership.**
The `Java_com_intsig_...` symbols are tied to proprietary Java/Kotlin
wrappers. Do not guess JNI signatures or call these entry points as if
they were compatible C APIs.

## Current DocScanner runtime

- **Used:** independently authored `libds_pagescanner.so` for native
  contour proposals and adaptive document enhancement.
- **Used:** Android/OpenCV 4.10.0 dependency plus bounded Kotlin fallback.
- **Optional, not used:** eleven user-supplied ELF libraries can be packaged
  for controlled local investigation via `docscannerIncludeImportedNative`.
  This is OFF in normal CI/release APKs.
- **Diagnostics:** `getNativeLibraryStatus` checks extracted and APK-embedded
  ELF presence without loading proprietary libraries.
- **CI:** host C++ regression and JNI symbol compile checks, release R8
  keep rules, ARM64-only APK build and final packaged ABI verification.

## Remaining verification before any imported-library API use

1. Establish usage/distribution rights and identify the exact Java wrappers.
2. Obtain method signatures, initialization routines, required models/assets,
   pixel formats, ownership rules, synchronization requirements.
3. Test on isolated ARM64 Android hardware with crash capture and memory
   limits; do not call directly from Flutter UI or camera main thread.
4. Evaluate compatibility with bundled OpenCV; avoid symbol collisions and
   conflicts with the application's other native libraries.
5. Confirm quality and repeatability against DocScanner's independent engine;
   retain a safe fallback on errors or unavailable ABI.
