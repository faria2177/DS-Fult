# Bundled models

## u2netp.onnx

- What: U²-Net "small" (U2NETP) salient-object segmentation, used to locate
  the document in an imported photo before the four corners are fitted.
- Authors: Xuebin Qin et al., "U²-Net: Going Deeper with Nested U-Structure
  for Salient Object Detection" — https://github.com/xuebinqin/U-2-Net
- License: Apache License 2.0 (https://www.apache.org/licenses/LICENSE-2.0)
- ONNX export obtained from the rembg project releases (MIT):
  https://github.com/danielgatis/rembg/releases/download/v0.0.0/u2netp.onnx
- SHA-256: 309c8469258dda742793dce0ebea8e6dd393174f89934733ecc8b14c76f4ddd8
- Input: 1x3x320x320 RGB, ImageNet mean/std. Output used: `1959` (finest map).

The file is unmodified. It runs fully on-device through OpenCV DNN.
