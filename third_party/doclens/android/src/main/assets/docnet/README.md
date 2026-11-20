# DocNet model (DocScanner's own)

- `docnet.param` / `docnet.bin`: ncnn format, exported by `tool/docnet/export.py`
  from weights trained by `tool/docnet/train.py` on images made by
  `tool/docnet/make_data.py` (fully synthetic: no real photos, no personal data).
- Input 1×3×160×160 RGB in [0, 1] (photo squashed to a square), output 1×1×80×80
  logits of "document pixel". About 0.13 M parameters.
- Run by `libds_docnet.so` (third_party/doclens/android/src/main/cpp/ds_docnet_jni.cpp).

## ncnn

The inference engine is Tencent ncnn 20241226 (BSD 3-Clause License,
https://github.com/Tencent/ncnn), linked statically. The Android prebuilt is
downloaded at build time by CMake (pinned by SHA-256).

## Recipe (v0.5.64)

    python3 tool/docnet/make_data.py c.npz 7000 21
    python3 tool/docnet/make_data.py d.npz 7000 22
    python3 tool/docnet/train.py c.npz d.npz --out docnet.pt --epochs 16
    python3 tool/docnet/average.py swa.pt docnet.pt.e1{0,1,2,3,4,5,6}
    python3 tool/docnet/export.py swa.pt third_party/doclens/android/src/main/assets/docnet

Synthetic validation mIoU 0.95; quad IoU on the 12 emulator scenes 0.94 (mean).
