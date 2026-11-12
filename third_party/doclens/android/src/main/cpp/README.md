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
