#!/usr/bin/env python3
"""Verify the shipped DocScanner APK contains the independent ARM64 engine.

No proprietary binaries may be present in the default CI release. This tool
checks ZIP entries only; it does not execute or reverse-engineer .so files.
"""
from pathlib import Path
import sys
from zipfile import ZipFile, BadZipFile

DEFAULT_APK = Path("build/app/outputs/flutter-apk/app-arm64-v8a-release.apk")
UNEXPECTED_IMPORTS = {
    "libpagescanner.so",
    "libscannercs.so",
    "libimageprocessor.so",
    "libmagicenhancer.so",
    "libenhance4draft.so",
    "liboctopus_classifier.so",
    "libMNN.so",
    "libncnn.so",
    "libCVNN.so",
    "libmainstone.so",
}


def verify(path: Path) -> None:
    if not path.is_file():
        raise FileNotFoundError(f"ARM64 APK not found: {path}")
    with ZipFile(path) as archive:
        native_files = {
            name for name in archive.namelist()
            if name.startswith("lib/") and name.endswith(".so")
        }
    own_engine = "lib/arm64-v8a/libds_pagescanner.so"
    if own_engine not in native_files:
        raise ValueError("DocScanner's libds_pagescanner.so is missing from ARM64 APK")
    other_abis = sorted({
        name.split("/")[1]
        for name in native_files
        if name.count("/") >= 2 and not name.startswith("lib/arm64-v8a/")
    })
    if other_abis:
        raise ValueError(f"Non-ARM64 libraries bundled: {other_abis}")
    imported = sorted({
        name.rsplit("/", 1)[-1]
        for name in native_files
        if name.rsplit("/", 1)[-1] in UNEXPECTED_IMPORTS
    })
    if imported:
        raise ValueError(f"Unapproved third-party libraries in default APK: {imported}")
    print(f"PASS: ARM64 APK contains DocScanner native engine ({len(native_files)} native libs)")
    print(f"Verified APK: {path}")


if __name__ == "__main__":
    try:
        verify(Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_APK)
    except (FileNotFoundError, ValueError, BadZipFile) as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        sys.exit(1)
