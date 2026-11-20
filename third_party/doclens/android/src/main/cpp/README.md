# DocScanner Native Document Boundary Engine (v1)

This directory builds application-owned libds_pagescanner.so through
Android NDK / CMake, independently of the user-provided proprietary
CamScanner binaries. The shared library is packaged automatically by
Android Gradle for the release APK's supported ABIs; **do not copy** it
manually to jniLibs, and do not include CamScanner .so archives.

## Architecture

- ds_page_scanner.cpp: pure C++17, host-testable document colour masks,
  connected-component isolation, four-corner geometry and four-side
  boundary contrast. Processing is limited to an EXIF-upright still image
  with a 512px long edge; the original full-resolution image is untouched.
- ds_pagescanner_jni.cpp: thin JNI bridge to an int[] ARGB image.
- NativePageScanner.kt: lazy load, strict JNI response validation, safe
  return-null if an ABI is unavailable.
- QuadDetector.kt: treats native results as **proposals**, compares them
  with existing Kotlin/OpenCV/colour-mask contours and preserves the old
  fallback when boundaries are uncertain.

This is image processing, not an AI model. A calibrated quality score
needs a labelled collection of real camera/gallery samples. No
CamScanner-like accuracy percentage is claimed.

## Native tests

On a developer machine with g++:
g++ -std=c++17 -O2 -Wall -Wextra -pedantic \
    src/main/cpp/ds_page_scanner.cpp \
    src/test/cpp/ds_page_scanner_test.cpp \
    -o /tmp/ds_native_scan_test
/tmp/ds_native_scan_test

The GitHub workflow also runs native host tests, the existing Android
Kotlin unit tests, Flutter analyze/tests and the release APK build.

## Safety

Native results are not trusted blindly. Reject malformed quads, unusual
coverage, self-intersection, background/frame overlaps and weak outer
edge evidence. If confidence is inadequate, leave the original still
available for manual crop. Never auto-trigger a shutter.

## libds_scannercore.so (scanner core, v0.5.63)

- ds_scanner_core.cpp: `FindPaperRegion` (Otsu + low-chroma paper mask,
  hole fill, opening against rails/cables, largest component, hull →
  four corners) and `MagicEnhance` / `IsNeutralDocument` (paper map from
  per-block 95th percentile → divide → tone curve → unsharp; coloured ink
  kept). Native twins of lib/src/services/paper_region_detector.dart and
  scanDocument() in image_processor.dart, which remain the fallback.
- ds_scanner_core_jni.cpp: `NativeScannerCore.magicEnhanceNative` /
  `paperRegionNative`; Kotlin wrapper NativeScannerCore.kt; method channel
  `nativeMagicEnhance` / `nativePaperRegion`.
- Host tests: src/test/cpp/ds_scanner_core_test.cpp (CI, with ASan/UBSan).
