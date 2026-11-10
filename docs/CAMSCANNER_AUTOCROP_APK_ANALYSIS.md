# CamScanner APK Auto Crop — Static Comparison (2026-11-10)

This document records observable technical evidence from three user-supplied
CamScanner APK splits, and the independently implemented DocScanner changes.
It does **not** reproduce CamScanner's executable code, proprietary trained
models or assets. Symbol names establish capabilities, not the exact active
algorithm or measured accuracy on a specific device.

## Inspected APKs

| Input | SHA-256 |
| --- | --- |
| `base.apk` | `d2bed329bd41f33352c364e55952964fe4df5cee09f833d4543bd8b266455d56` |
| `split_config.arm64_v8a.apk` | `b2ec36587d5a582c797bd54dce526ab80645baf08d65857df3fe0f0d21d22f31` |
| `split_resource_assets.apk` | `91d59c0853ecbd0f4e8f37108a99cee42c86c53e32008fb2dc794a073d65785a` |

Static methods: ZIP manifest inventory and ELF dynamic-symbol inspection.
The resource split includes `assets/mobile_ocr.data`; its presence alone is
not evidence of Auto Crop model use. The base APK contains Flutter assets,
while the inspected scanning entry points are native Android/JNI symbols.

## Relevant native components

| Native library | Directly observed exported symbols | Supported inference |
| --- | --- | --- |
| `libscannercs.so` | `ScannerEngine_detectBorder`, `ScannerEngine_detectYuvImage`, `DetectBoundInVideo`, `DetectCardInVideo`, `validateAndAdjustCorners` | Distinct live-image and card boundary detection plus geometric validation |
| `libpagescanner.so` | `PageScanner_DetectBorderYUV`, `pagescan::findLines_EDLine`, `adjustCorners`, `documentCrop`, `dewarp_process_new`, `PageScanner_DetectCurveBorder` | Line-based boundary recovery, perspective crop and curved-page correction |
| `libopencv.so` | OpenCV native implementation | Classical computer-vision operations are available |
| `libCVNN.so`, `libMNN.so`, `libncnn.so` | Neural-network runtimes | ML inference is available, but this inspection does **not** establish which Auto Crop pathways use it |

The published symbol names do not disclose corner-scoring thresholds, model
weights, internal dispatch rules or CamScanner's success rate. It would be
incorrect to promise pixel-identical results from these APKs alone.

## Independent DocScanner implementation: 0.5.33

1. **Live mode remains responsive.** Camera frames keep the existing fast
   contour, colour-background and temporal-smoothing path; Auto Capture stays
   off as requested.
2. **Still mode now explores all boundary families.** Full-resolution shutter
   images continue past strong *inner* table contours to try Hough lines and
   morphology before choosing a reliable outer sheet. A captured still uses a
   1280px working image; the live-preview size is unchanged.
3. **The line fallback needs three supported sides.** A guessed quadrilateral
   assembled from unrelated table rows or background edges is rejected.
   Still-image corner refinement cannot drift far from the selected page.
4. **Gallery imports protect source content.** Compact interior polygons
   cannot silently replace a complete page or ID photo. If normal Scan finds
   only an internal name block, a card-specific second pass may substitute a
   larger, geometrically credible quad enclosing it; otherwise the complete
   original stays available for manual corner adjustment.
5. **ID-card mode remains distinct.** The explicit card workflow retains its
   own card detector instead of applying A4-only geometry limits.

## Acceptance tests still required on a real HONOR VKP-NX9

- Repeat video `381847(1).mp4` with its original NID photo: neither automatic
  crop nor PDF export may drop the portrait, header or number.
- Repeat `381772.mp4`: dense portrait A4 table must not become a landscape
  inner-row crop. Test both orientations and verify the page's four borders.
- Test faint paper/white desk, coloured fabric, glare, shadows, small receipts,
  slanted cards, stacked sheets and corner occlusion. Measure corner error
  against manually marked source photos and the percentage of safe fallbacks.
- Record preview FPS, shutter-to-edit latency and memory peak against 0.5.32,
  because higher still resolution and extra search stages cost more CPU.
- Run Android native tests, Flutter analyzer/tests and APK build in CI; then
  install the candidate and inspect the actual saved images and PDFs.

This version improves the independent scanner's boundary search and safety.
It is **not** a validated guarantee of flawless detection in arbitrary images.
