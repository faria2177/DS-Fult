#!/usr/bin/env python3
"""Import a user-supplied ARM64 JNI archive for optional *local* packaging.

Usage: python tools/prepare_camscanner_native.py path/to/base.zip
Binary files remain Git-ignored and excluded from normal builds. This tool
does not enable or call any proprietary JNI algorithm.
"""
import hashlib
import json
import pathlib
import struct
import sys
import zipfile

LIBRARIES = (
    "libpagescanner.so", "libscannercs.so", "libopencv.so",
    "libimageprocessor.so", "libmagicenhancer.so",
    "libenhance4draft.so", "liboctopus_classifier.so",
    "libMNN.so", "libncnn.so", "libCVNN.so", "libmainstone.so",
)
RELATIVE = pathlib.Path(
    "third_party/doclens/android/src/main/optionalNativeJniLibs/arm64-v8a"
)


def main() -> int:
    if len(sys.argv) != 2:
        print("Usage: python tools/prepare_camscanner_native.py /path/to/base.zip")
        return 2
    root = pathlib.Path(__file__).resolve().parent.parent
    archive = pathlib.Path(sys.argv[1]).expanduser().resolve()
    if not archive.is_file():
        print(f"File not found: {archive}", file=sys.stderr)
        return 2
    output = root / RELATIVE
    blobs = {}
    with zipfile.ZipFile(archive) as z:
        paths = [p for p in z.namelist() if p.endswith(".so")]
        for name in LIBRARIES:
            matches = [
                p for p in paths
                if p == f"so/{name}" or p.endswith(f"/arm64-v8a/{name}")
            ]
            if len(matches) != 1:
                raise ValueError(
                    f"{name}: expected one ARM64 source, got {len(matches)}"
                )
            data = z.read(matches[0])
            if (
                len(data) < 64 or data[:4] != b"\x7fELF" or
                data[4] != 2 or data[5] != 1 or
                struct.unpack_from("<H", data, 18)[0] != 183
            ):
                raise ValueError(f"{name}: not 64-bit ARM64 ELF")
            blobs[name] = data
    output.mkdir(parents=True, exist_ok=True)
    metadata = {}
    for name, data in blobs.items():
        (output / name).write_bytes(data)
        metadata[name] = {
            "size_bytes": len(data),
            "sha256": hashlib.sha256(data).hexdigest(),
        }
    (output.parent / "import-manifest.json").write_text(
        json.dumps({
            "abi": "arm64-v8a",
            "source_archive": archive.name,
            "libraries": metadata,
        }, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"Prepared {len(blobs)} ARM64 libraries in {output}")
    print("Optional Gradle property: docscannerIncludeImportedNative=true")
    print("WARNING: This packages libraries only; JNI methods are not called.")
    print("Only distribute these binaries if you have the necessary rights.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
