# DocScanner scan workflow — CamScanner-style user journey

> This document defines **DocScanner's implementation**, reconstructed from
> observed capture/edit screens, publicly inspectable APK structure and the
> user's comparison videos. CamScanner's private internal runtime sequence,
> model thresholds and proprietary source code are not known or reused.
> Matching UX and output quality is a goal, not a verified equivalence.

## Pipeline

```mermaid
flowchart TD
    A[Scan / Import Images / Import File / ID Card] --> B{Source}
    B -->|Camera| C[Live CameraX preview + stable 4-corner overlay]
    B -->|Gallery / PDF images| D[Select photos and import settings]
    C --> E[Manual shutter - auto capture OFF by default]
    D --> F[EXIF-upright still image]
    E --> F
    F --> G[Try consented Online First only if configured]
    G --> H[OpenCV still detector + independent native/Dart proposals]
    H --> I{Credible complete outer boundary?}
    I -->|Yes| J[Safe pixel-edge refinement + perspective correction]
    I -->|No| K[Adjust Corners: 4 handles / edge handles / rotate]
    K --> L{User confirms crop?}
    L -->|Yes| J
    L -->|Cancel / not confirmed| M[Keep full original - never guess]
    J --> N[Selected filter: Original/Enhance/Magic Pro/B&W/etc]
    M --> N
    N --> O[Preview: one scanned page or ordered batch]
    O --> P[Document library + edit pages / add / retake / OCR]
    P --> Q[Local PDF / JPG / PNG / Word / Excel / print / share]
```

## Canonical user-facing workflow (screen-by-screen)

This is the **DocScanner product contract**, inspired by the observed
CamScanner user journey. It is not a claim about CamScanner's private
implementation. Use the same order for camera, gallery and imported images:

| Step | User sees | Engine does | Back / failure behaviour |
| --- | --- | --- | --- |
| 1. Acquire | Scan camera / Gallery / Device / ID Cards | Capture full-resolution JPEG, preserve EXIF orientation and source path | Cancel without saving |
| 2. Live outline | Four-corner mint overlay; manual shutter | CameraX preview detection with stable tracking; no forced shutter | No outline must not block manual shutter |
| 3. Still detection | Processing indicator only when needed | Re-detect from upright full-resolution still; opt-in online detector first when configured, otherwise independent native/OpenCV and local fallback | Network timeout or missing model immediately falls back locally |
| 4. Verify boundary | Whole document, never internal title/table | Validate convex quad, all four visible corners, coverage, geometry and boundary evidence; reject false outer holder/desk | If uncertain, open four-corner adjustment with source intact |
| 5. Adjust corners | Full original with four corner handles, four side handles, Rotate, Auto Crop retry and Done | Refine using pixel evidence, reject large corner drift, warp only confirmed corners | Back preserves original; invalid quad cannot be applied |
| 6. Enhance | Original, Enhance, Magic Pro, B&W and other existing presets | Crop and perspective-warp **before** enhancement; avoid aggressive paper whitening on uncropped images | Original remains available; filter changes are reversible |
| 7. Review | Single: exactly one page; Batch: ordered page grid | Retain raw source, unfiltered crop and filtered working copy separately | Retake, add, rotate, reorder and re-crop from original |
| 8. Save | Named local document in Home/Files | Copy accepted pages into app-private storage and persist metadata | Never duplicate, drop or reorder a page silently |
| 9. Convert | PDF, JPG/PNG, Extract Text, To Word, To Excel, print/share | Local PDF/image export; OCR/AI conversion follows its separate explicit consent policy | Failed conversion must not corrupt the saved scan |

### Single Scan navigation

`Home → Scan → Camera preview → Shutter → (Adjust Corners if needed)
→ Enhance/Preview → Done → One-page document detail`.

The shutter remains manual by default. A successful native perspective crop
must not be cropped again from a stale preview quad. The document detail
screen must show **only the captured page**, not an empty multi-page loader.

### Batch Scan navigation

`Home → Scan → Batch → Capture N pages → Finish → Review unresolved
corners → Apply filter per accepted page → Ordered N-page grid → Save`.

Keep the original capture order. For every page store its own four-corner
state, rotation, effect, raw source and output path. Review is limited to
uncertain pages, not a mandatory repeated prompt for every confident page.

### Gallery / Device import navigation

`Home/Tools → Import Images or Import File → Select and order → Auto Crop
toggle + effect → Detect → Review uncertain pages → Preview → Save`.

Imported images use the same *still-image* detector and safety policy as
camera captures. PDF input is rasterized per selected page before entering
this sequence. Auto Crop OFF must not silently crop or display an
unrequested corner editor.

### ID Card navigation

`Tools → ID Card → Choose template → Front source → Four-corner adjust
→ Confirm → Back source → Four-corner adjust → Confirm → Two-sided A4
layout preview → Save/Export`.

Use card-shaped geometry, not A4 detection. Keep front/back independently
editable during capture. Never crop only a face, name or printed border.
A single A4 export must contain both accepted sides in their selected
positions. Preserving both raw sides after saving the composite remains a
separate tracked limitation.

### Required engineering state transitions

```mermaid
stateDiagram-v2
    [*] --> Acquiring
    Acquiring --> Detecting: shutter or import
    Detecting --> Cropped: validated outside quad
    Detecting --> NeedsReview: no safe outside quad
    NeedsReview --> Cropped: user confirms valid corners
    NeedsReview --> Original: cancel / keep source
    Acquiring --> Original: Auto Crop disabled
    Cropped --> Enhancing
    Original --> Enhancing
    Enhancing --> Preview
    Preview --> Acquiring: add page / retake
    Preview --> Saved: explicit Done
    Saved --> Exported: explicit export
```

**Acceptance gates:** never discard the raw image; do not accept a quad
that cuts a header or table; do not auto-accept an interior text rectangle;
do not make a network request without opt-in; do not trigger a save
notification on intermediate edits; do not let bottom actions overlap
Android navigation bars. Real-camera A4/NID/glare/low-light tests are
mandatory before claiming comparable quality.

## Entry modes

### Single scan
1. Camera opens with a stable rectangular overlay. Manual shutter is the
   default; camera auto-capture is OFF unless explicitly switched on.
2. The captured full-resolution upright original is retained.
3. Re-detect corners from the captured still rather than reusing a stale
   preview outline. Prefer complete paper/card borders to internal labels.
4. Apply a reliable perspective crop; if uncertain, open Adjust Corners
   and keep the full original on Cancel or unconfirmed handles.
5. Apply the selected filter to the cropped output, then show **one page** in
   the document editor. Rotate, crop, retake, extract text and export remain
   available. The original stays available for correction where supported.

### Batch scan / Import Images
1. Select photos; reorder/selection follows original selected order.
2. When Auto Crop is checked, detect each photo using the same still-image
   boundary policy. At most two auto-crop operations run concurrently.
3. High-confidence pages advance directly. Only uncertain pages open the
   multi-page Adjust Corners screen. Each page has independent handles,
   Auto Crop retry, rotation and page navigation.
4. Confirmed manual corrections replace the corresponding **working output**
   only; canceled/unmodified pages retain the originals. No photo disappears.
5. Enhancement applies **after** perspective cropping, with document-only
   bleaching disabled for uncropped backgrounds. The ordered results open
   the existing multi-page document grid and editing/export tools.

### ID card / Driver license / Bank card
1. The separate Front/Back (two-sided) workflow remains in `IdCardScreen`.
2. Crop/detect with `preferIdCardBounds=true`, not a forced A4 aspect ratio.
3. Never substitute an inner name/portrait rectangle for the entire card.
4. Users may correct each source side, rotate, enhance and compare.
5. Complete two-sided documents are arranged onto one A4 output through the
   existing `IdCardPageComposer`, with the selected template maintained.

## Runtime ownership

| Stage | Current implementation |
| --- | --- |
| Live overlay / CameraX | `third_party/doclens/android/src/main/kotlin/dev/doclens/doclens/ScannerSession.kt`, `OpenCvBoundaryAdapter.kt` |
| Still-image boundary proposals | `QuadDetector.kt`, `NativePageScanner.kt`, `lib/src/services/offline_document_contour.dart` |
| Safe contour selection | `lib/src/services/document_edges.dart` |
| Pixel edge refinement | `lib/src/services/quad_edge_refiner.dart` |
| Source/crop/review state | `lib/src/services/scan_workflow.dart` |
| Uncertain four-corner review | `lib/src/screens/batch_crop_screen.dart` |
| Gallery orchestration | `lib/src/screens/gallery_import_review_screen.dart` |
| Camera orchestration | `lib/src/screens/camera_screen.dart` |
| Perspective correction | `ImageWarper.kt` and `lib/src/services/image_processor.dart` fallback |
| Enhancement | `lib/src/services/image_processor.dart`; optional independent `libds_pagescanner.so` native pathway |
| Preview and edit tools | `lib/src/screens/document_screen.dart`, `document_detail_screen.dart` |
| Two-sided ID composer | `lib/src/screens/id_card_screen.dart`, `lib/src/services/id_card_page_composer.dart` |
| Local document persistence | `lib/src/storage/document_store.dart`, `HomeShell` |
| Export tools | `lib/src/services/document_export.dart` and individual Office/PDF services |

## Durable source preservation

A saved page now has two different editing references:

- `path`: currently displayed scan (crop + enhancement/edit).
- `originalPath`: perspective-corrected, unfiltered baseline so changing
  Enhance/Magic Pro/B&W never accidentally removes the crop.
- `rawSourcePath`: separate, full upright original camera/gallery image,
  stored in the app's private file library. Reopening Adjust Corners uses
  this image and can recover a clipped page header or ID photograph.

The optional `rawSourcePath` field is backward-compatible: old documents
without it still use their current image. Gallery import and normal CameraX
capture now pass original files into `DocumentStore.createFromPaths`.
The separate ID-card A4 composite flow has its own source-side editor;
a saved composite is not yet a lossless two-source ID project.

## Hard invariants

- **Never cut away uncertain content**. If valid four outside corners are
  unavailable, offer adjustment or preserve the original untouched.
- **No fabricated corner coordinates**. Strong printed table lines and
  notebook/holder outlines must not override a verified outer boundary.
- **Crop before enhancement**. Never use strong paper whitening on a raw
  background if the page has not been cropped. Preserve explicit Original.
- **Preserve page count and source order**. Do not duplicate/drop pages.
- **No invisible uploads**. Online First requires a saved user opt-in and a
  private HTTPS endpoint; otherwise local processing continues.
- **No proprietary JNI invocation**. User-provided CamScanner binaries are
  optional investigation-only and OFF in normal APKs; the app uses its own
  C++ engine, Kotlin/OpenCV and Dart filters.
- **No save notification for intermediate edits**. Notify only when the
  existing document save/export behavior calls for it.
- **Stable UI**. No hidden bottom controls or camera screen leaks while a
  full-screen crop editor owns navigation.

## What is implemented in this change

- Added typed `ScanWorkflowBatch` and `ScanBoundaryState` so every
  imported page is explicitly cropped, needs review, or intentionally original.
- Gallery and camera paths open `BatchCropScreen` for uncertain stills
  before enhancement/finish. The ID flag propagates to the crop detector.
- Canceled edits cannot overwrite source photos; manual adjustments use new
  temporary output files.
- Auto Crop disabled continues to use the original without prompting.
- Added workflow policy tests. Existing image, contour, OCR and PDF tools
  are unchanged.

## Validation still required

- Run `flutter analyze` and `flutter test` in GitHub Actions.
- Build ARM64 APK, verify `libds_pagescanner.so` packaging, then test on
  real Android hardware.
- Compare captured **identical originals** against CamScanner output across
  A4, legal, skewed page, faint border, patterned background, gold NID on
  ruled paper, reflective sleeve, glare, shadow and low-light scenes.
- Record four-corner localization error, false-crop rate, OCR legibility and
  visual quality, not just number of recognized contours.
- Device testing and measured CamScanner-equivalent accuracy are **not
  established** by this workflow definition.
