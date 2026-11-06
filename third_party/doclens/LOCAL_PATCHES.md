# Locally maintained doclens 0.0.12

The source in this folder is based on the MIT-licensed upstream
[`govindmaheshwari2/doclens`](https://github.com/govindmaheshwari2/doclens),
commit `795b2dbf6689640a24aab827a347ab4e08cc0ef3`.
The original license is preserved in `LICENSE`.

## DS-Fult scanner fixes

- `android/src/main/kotlin/dev/doclens/doclens/QuadDetector.kt`:
  evaluate the twelve largest viable connected components instead of only the
  biggest one. Rank convex quadrilaterals using solidity, centrality, bounded
  coverage and border isolation. This reduces false targets when an ID card is
  smaller than bright clothing, dark desks, and other surrounding clutter.
- `android/src/test/kotlin/dev/doclens/doclens/QuadDetectorTest.kt`:
  synthetic bright/dark foreground and border-clutter regression tests.
- `lib/src/quad_smoother.dart`:
  reject brief competing document quads and require consecutive candidate
  matches before changing the green outline. Hide a stale outline if the
  detector continues to disagree. Tested in host `test/quad_smoother_test.dart`.

The host app disables auto capture explicitly in its `ScannerConfig` and in
both single-page and batch scanner widgets. Edge detection, corner adjustment,
manual shutter and perspective crop remain enabled.

When updating upstream, review these changes before replacing the vendored
package. Full real-device validation is needed for camera frame rotation,
lighting and phone-specific preview mapping.
