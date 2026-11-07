# DC — Flutter (DS-Fult)

Local-first Android document scanner with an original DS-branded, CamScanner-inspired interface.
The app does **not** include CamScanner's proprietary code, artwork, cloud services or trademarks.

## Six reference-video tool interfaces — v0.5.8

- The **Tools** entries for Add Watermark, Smart Erase, Merge Files, Compress,
  Reorder Pages and Lock now use original Flutter layouts patterned on the six
  supplied recordings: charcoal tool backgrounds, turquoise accents, square
  action buttons, source document tiles and a bottom confirm bar where shown.
- **Add Watermark** has a collapsible adjustment sheet with Single/Tile,
  colour swatches, Opacity/Size/Rotate and a preview on the source page.
  The collapsed bar exposes Edit Text, Adjust and Remove Watermark.
- **Smart Erase** now has Magic, Handwriting and Text tabs, stroke thickness,
  brush/rectangle selection, Compare, Undo/Redo and an explicit Save action.
  All modes edit pixels locally; the mode tabs are editing affordances, **not**
  proprietary automatic AI removal. Complex textures can still show seams.
- **Merge Files** first selects existing documents or imports photos, then
  shows the video-style draggable document list, Keep Originals, Add File,
  Merge Documents and preview. Compression has Medium/High cards, local size
  measurement and a shareable result; reorder has a two-column grid with
  Select All and drag-to-sort.
- **Lock** opens the light document picker followed by a dark password sheet,
  including show/hide and matching-six-character validation. The app protects
  access to its library, **not** the exported PDF bytes. Ask AI and paywalls
  are deliberately absent. Layouts adapt to screen width and Android bars,
  so exact pixel positions may differ by device.

## Reference-video Tools update — v0.5.7

- **Add Watermark** now opens directly from Tools. The on-device preview and
  exported full-resolution PNG share the same drawing code for **Single/Tile**
  layouts, placement, colours, opacity, size and ±45° rotation. The previous
  page image is retained so **Remove Last Watermark** restores only the most
  recent watermark; subsequent unrelated edits clear this undo reference to
  prevent accidental loss of later work.
- **Reorder Pages** from Tools shows the reference-style two-column page grid,
  teal selected state and long-press drag-to-sort. Cancel discards the staged
  order; Confirm saves it in one index update without touching image files.
- **Compress PDF** offers **Medium** (better quality) and **High** (smaller
  file), measures source/result PDF size, previews the first page, and shares
  the generated local PDF. Compression does not overwrite the stored scan.
- **Lock PDF** is no longer a placeholder: the password and confirmation must
  match and contain at least six characters. It uses the same app-level PIN
  hash as the existing document unlock screen. This **does not encrypt files**
  or exported PDFs; real at-rest encryption remains a separate engineering task.
- Existing offline Merge Documents is retained. The Magic/Handwriting/Text
  visual editor was subsequently added in v0.5.8, without proprietary
  semantic segmentation, cloud AI, paywalls or Ask AI options.

## Repeat-scan crop reliability — v0.5.6

- The supplied 38-second video exposed a third **Add Pages** capture that
  retained the blue cloth and wide margins despite the first two pages being
  cropped. CameraX now tests a second still-image candidate for **neutral,
  bright paper surrounded by a saturated-colour background**. This fallback
  uses colour separation rather than luma alone, and does not guess a page
  when the background is an ordinary white/grey surface.
- If a valid colour-separated page is substantially larger than the original
  OpenCV candidate, prefer the complete page to avoid inward clipping.
  The normal OpenCV pipeline remains authoritative for ordinary documents.
- With Auto Crop enabled, a capture without a successful crop now opens
  **Adjust corners** for the user automatically and warns in Preview that
  the full raw image still contains the background. It no longer silently
  presents a non-cropped page as though automatic cropping succeeded.
- Native regression tests cover pale, slightly textured paper on blue fabric
  and ensure uniform neutral backgrounds do not generate fake document edges.
  Existing saved files are not altered; physical-device testing is still
  needed for unusual lighting, glare and stacked pages.

## Files multi-selection and management — v0.5.5

- **Files** now has the video-reference list/grid toggle, date/name/page-count
  sorting, search, folder picker, folder create/rename/remove, long-press
  selection, select-all, and checkboxes. The app bottom navigation is hidden
  while selecting so all bottom actions remain accessible above system bars.
- Single selection offers **Share, Move/Copy, Rename, Delete, More**. Multiple
  selections enable **Merge** and batch sharing, moving, copying, deletion,
  tags, and app-level locking. Move and Copy offer local folder destinations.
- **Share** exports real PDFs, offline OCR Word (one document), long image
  (one document), individual page images, or saves pages to Android Gallery.
  **Share Link** explains why an offline-only app cannot make a hosted URL.
- **Merge Documents** lets you add/remove source documents, drag to reorder,
  preview all pages, choose **Keep originals**, and save a named new document.
- **More** contains Send to PC (Android sharing), Print, PDF to Images,
  Add to Home Screen (Android launcher pin shortcut), Tags and Lock. A pinned
  shortcut reopens its chosen local document; shortcuts depend on launcher
  support. Locks use the same per-document app PIN format as Document Detail.
- Deleting a document removes its library entry, while source images are
  retained for technical recovery; there is no in-app seven-day Trash yet.
  No Ask AI or cloud integration is added.

## Watermark and Brush editing — v0.5.4

- **Edit → Images → Add Watermark** opens a dedicated image editing screen,
  not PDF Tools. Users can choose watermark text, colour, opacity, size,
  and top-left/center/bottom-right position. The text is applied to a new
  full-resolution PNG on the current page, with the untouched original
  retained for Compare/Original. All processing happens on the device.
- **Edit → Images → Brush** opens a freehand annotation tool with ink colours,
  adjustable width, undo, and clear. Every completed stroke retains its
  own chosen ink colour and width, including in the saved image. The **Sign**
  action remains a separate, simpler signature workflow.
- Composer tests verify the watermark pixels, unchanged background and
  independent red/blue brush strokes. There is still no Ask AI button or
  cloud document handling.

## Document detail, More, editor and sharing reference — v0.5.3

- New dark document detail screen opens scanned pages as a two-column grid,
  with **Add Pages**, editable name, **Tags**, info and a **More** menu.
  Long-press pages for visible multi-selection checks and **Share**, **Save
  to Gallery**, **Move/Copy**, **Collage** and **Delete**. **Manage Pages**
  opens the existing functional drag-reorder editor.
- The **More** sheet now matches the reference's four groups: Edit PDF,
  Send to PC, Save to Gallery and Print; Convert (Word, Excel); Smart Tools
  (Extract Text, Collage, Translate, Compress, No Handwriting, Create Quiz,
  Extract Formulas, Read Mode); Manage (Manage Pages, Lock, Merge Files,
  Copy/Move), plus Delete. **Ask AI is intentionally absent.**
- New scans open the processing/compare/filter/retake/crop preview before
  the document grid. Opening an existing page enters the Images/Markup/Page
  editor with crop, filters, OCR, image text edits, erase, retake, sign,
  brush, mosaic, page title and PDF watermark actions.
- Share supports real PDF, offline OCR-based Word, page images and a stitched
  long image. The two-column Collage is distinct from a long image. Android
  MediaStore writes Gallery files on Android 10+ through the bundled plugin.
- Lock is **only an access PIN inside DocScanner**, not encrypted storage or
  an encrypted PDF. **Send to PC** invokes Android's file-share chooser.
  Translation sends extracted text to an installed translation app; the app
  itself does not translate or upload. Quiz and formula extraction are
  limited local text heuristics, not advanced AI or a math-vision model.
  **Share Link** is shown with a local-only explanation because no hosted
  link can exist without a cloud server. The screenshot's proprietary
  processing results and exact fonts are not included.

## Me → Scan preferences and Tools cleanup — v0.5.2

- **Me → Scan** opens the same seven-preference page as the camera's
  **three-dot menu → More Settings**: Auto Adjust Borders, Adjust After Each
  Scan, Start with Camera, Use System Camera, Import from Gallery, Save Scans
  to Gallery After Scanning, and Double-Focus.
- All switches edit the live scanner preferences and are saved to the same
  on-device record. Rapid consecutive saves are ordered so the last change
  survives leaving Me, reopening the scanner, and restarting the app.
- Removed these nine entries from the **Tools grid**: Mega Scan, Long
  Document, Driver License, Bank Card, Photo Translation, Scan Code, To PPT,
  Erase Marks, and Restore Photo. ID Card templates and the Home quick
  actions are unchanged; underlying service code remains available if needed.
- System Camera only overrides **Single** capture; Batch continues to use
  the in-app camera. Gallery filter preference likewise only applies in
  Single mode, matching the settings page's explanations.

## Camera mode transition fix — v0.5.1

- **Single ↔ Batch** now switches Flutter UI state without stopping or
  recreating CameraX. No 350 ms black screen, lens re-open or contour tracker
  reset on the default configuration. When the uncommon Batch/auto-border
  setting requires a genuinely different native warp configuration, a safe
  rebind is still used.
- The **Scan ↔ ID Cards** tabs now share the *same running scanner preview*.
  ID Cards is an in-place overlay, not a second Flutter camera session.
  Native preview is fitted only once to avoid distorted/mirrored appearance.
- Entering a separate ID capture or external image picker still releases the
  current camera intentionally to avoid two CameraX owners racing.
- The ID Cards tab no longer shows **Smart Erase**, **Question Set**,
  **Translate** or **All Features**, as marked in the supplied screenshot.
- Transition and unwanted-option regression tests are included. This cannot
  guarantee zero texture-frame drops on every device until the target HONOR
  handset is tested, but removes the avoidable camera teardown and black gap.

## ID Cards reference flow — v0.5.0

- Tapping **ID Cards** in the Scan camera now opens a dedicated live-preview
  template chooser. The Home **ID Card** shortcut opens the same chooser.
- The six swipeable choices follow the supplied video: **General, ID Card,
  Driver License, Passport, Bank Card, Certificate**. Each choice changes
  the A4-copy illustration and the **Make it now** button launches that mode.
- The ID capture screen alone has the reference's white four-corner card
  brackets, Front/Back or document label, flash, HD, settings, undo/back,
  shutter and Import Images. Regular document scanning is unaffected.
- Wide ID/driver/bank cards use landscape guides; passport and certificate
  use a tall guide. One-sided modes accept one image; two-sided modes retain
  the existing per-side crop/rotate and final document flow.
- Back/close shows a discard confirmation. Cameras are released before
  opening a second capture screen to avoid Android camera ownership races.
- No sample photo or proprietary illustration from the reference app is
  redistributed; the A4 illustration is generated from Flutter widgets.
  The template guides, capture and on-device processing still need physical
  testing on the target HONOR Android device.

## Scan Effects, HD and Settings — v0.4.0

- The live Scan toolbar now opens the supplied reference's **11-item Effects
  grid**, **HD resolution picker** and **Settings** panel. The full seven-row
  More Settings screen mirrors the reference's labels and toggle order.
- Settings persist locally, including filter, orientation, Grid, sound,
  automatic shutter, auto-crop, accelerometer-powered spirit level, double
  focus, batch border review, system-camera preference, and gallery options.
- The HD picker enumerates **actual rear-camera JPEG resolutions** via
  Android Camera2; it doesn't promise unsupported 12M/8M modes. The chosen
  supported size is requested from CameraX. Photos up to 4096 pixels on the
  long side retain those pixels when decoding for perspective warping.
- After a scan is accepted, the selected effect runs in a Dart worker. Basic
  color/grayscale/B&W/shadow presets work offline. **No Watermark** and
  **No Handwriting** are conservative, experimental pixel heuristics, *not*
  CamScanner's proprietary AI models: they will not remove arbitrary marks
  reliably and can erase similarly coloured document content. Always check
  the preview. Filtering writes a separate file and never overwrites the
  unfiltered capture.
- On Android 10+, the gallery-save setting writes JPEG copies through
  MediaStore to `Pictures/DocScanner` without broad storage permissions.
  Older Android versions do not yet support this option.
- The separate PDF/file import picker is still outstanding; the existing
  image picker serves the Scan screen's Import shortcuts. Hardware controls
  and exact UI spacing require testing on the target HONOR phone.

## Framed Scan camera — v0.3.9

- Rebuilt the main Scan camera interface around the supplied reference image:
  black upper controls, bordered central live preview, Single/Batch selection,
  Scan / ID Cards tabs, and separate lower Import / shutter controls.
- Preserved native CameraX live detection, manual shutter, editable four-corner
  review and multi-page flow. Camera UI remains Flutter widgets, not a static
  screenshot. The existing gallery image picker currently handles both Import
  shortcuts; a separate PDF/file picker is still future work.
- Tightened document visibility checks to reject detected quadrilaterals
  clipped by the image edge. Small, valid ID-card-sized contours get more
  balanced scoring against large background patterns.
- Captures now start with natural (unfiltered) image pixels rather than a
  forced enhanced filter that could wash out light cards; users can choose a
  filter later in the document editor.
- Flutter UI tests and Kotlin geometry regression tests added. Real-camera
  testing on the target Android device remains necessary to verify parity.

## DS logo update — v0.3.8

- Uses the supplied navy, white and teal **DS** logo in the Home and Me screens.
- Ships Android density-specific launcher icons and Android 8+ adaptive icon
  resources. `tool/setup_android.sh` reapplies the icon whenever Flutter's
  Android host is regenerated by local builds or GitHub Actions.

## Scanner stability update — v0.3.7 (work in progress)

- Live CameraX YUV preview now supplies sampled **colour** (RGBA) as well as
  luminance to the multi-stage OpenCV detector. Its saturation-edge stage can
  distinguish similarly bright paper and backgrounds with different colours.
  Stride-aware YUV420 sampling supports padded and interleaved chroma planes;
  a malformed chroma plane retains the existing grayscale fallback. Added
  regression tests for colour contrast, pixel strides and downscaling.
- Full-resolution capture **never reuses a stale preview quad** when still-image
  detection fails. It preserves the complete upright photo for four-corner
  manual review instead of risking an irreversible wrong crop. A failed warp
  also retains the original capture for recovery.
- Auto Capture remains disabled in Single and Batch. Native detector performance,
  portrait preview mapping and scan accuracy still require physical-device
  testing in varied lighting and backgrounds.

## Earlier scanner milestones

- **Green edge stability (v0.3.4):** the live quad tracker now compares the
  size and position of consecutive candidate documents before moving its
  outline. A stray background shape must be detected consistently in three
  frames before the box switches; stale boxes disappear after sustained
  mismatches or missed frames. The median window is now seven frames to
  reduce motion lag. Added Flutter tests for jitter, outliers, movement,
  document switches and loss/recovery. The shutter stays **manual**.

- **Camera four-corner alignment fix (v0.3.3):** CameraX Preview,
  ImageAnalysis and ImageCapture now request the same 4:3 field of view.
  Previously a 16:9 preview and 4:3 detection buffer could stretch/move
  the live polygon relative to the real card (especially on tall phones).
- Still photos are now re-detected at capture time before perspective crop,
  preventing a stale preview-frame quad from being applied to a differently
  cropped full-resolution image. The original image remains available when
  detection fails, for manual corner adjustment.
- Stronger native quad rejection for shapes that touch frame edges, have
  pinched corners, or fail to resemble a convex page/card. Live detected
  outlines stay green while the operator moves closer or steadies the phone.
- Added Kotlin regression cases for a light card on a dark surface and a dark
  card on a light surface. Automatic shutter remains disabled.

- Flutter Material 3 UI: Home, Files, Scan, Tools, Me; light and dark modes.
- Native live document corner tracking with **manual shutter only** (auto
  capture disabled in Single and Batch), perspective dewarp and adjustable
  review using a locally patched MIT-licensed `doclens` engine; manual
  camera remains available for devices where the detector is unsuccessful.
- Auto edge detection uses four-corner smoothing, low-light and focus checks,
  multiple quad candidates rather than the largest image blob, and high-resolution capture. Light and dark
  documents can be scanned against contrasting backgrounds.
- The live preview now draws a **complete green four-sided border** along the
  detected document (rather than disconnected corner brackets), with seven-frame
  corner smoothing. Camera **Single / Batch**
  selection is on the scanner itself; switching modes releases CameraX first.
- Gallery imports use the same native four-corner detector and automatically
  crop/straighten reliable detections. When no reliable boundary is found the
  original image is preserved for manual cropping; no guessed crop is applied.
- Crop editor automatically proposes detected corners, lets the user redetect
  or reset them, and rejects crossed/degenerate quadrilaterals before warping.
- **Mega Scan** batch mode with manual shutter, thumbnail review,
  page sorting/deletion; **Long Document** mode for guided multi-shot stitching.
- HD camera capture, flash, gallery import and multi-page documents.
- Local document library, persistent folders, rename/move/delete and image previews.
- Manual four-corner perspective crop with a homography transform.
- Original, Auto, Enhance, **Shadow Free**, Magic Color, Grayscale, B&W filters.
  Auto/Enhance/Shadow Free now estimate local illumination to lift dark paper areas.
- ID Card / Driver License / Bank Card front-and-back workflows with a **hard two-image maximum**, including the gallery picker limit.
- Each captured/imported ID-card side can be tapped to adjust all four corners.
- Single A4 PDF with both sides of a card; standard multi-page PDF for documents.
- Share PDF/images, print via Android system print service.
- On-device **English/Latin OCR** plus **offline Bengali OCR** using the
  BSD-licensed `flutter_tesseract_ocr` plugin and `tessdata_fast` Bengali model
  bundled in the APK.
- Image text editor: tap an English OCR line to replace/erase it directly on the
  scanned image, tap to add text in English/Bengali, drag to erase a mark, undo
  recent edits. The original capture is retained.
- PDF organizer with reorder, extract selected pages into a new document,
  merge local documents, compressed PDF sharing and watermark on PDF export.
- Copy/share extracted TXT and custom **DS AI PROSINESS** processing animation.
- GitHub Actions release APK builds for ARM32, ARM64 and x86_64.

## Not yet implemented

**Not CamScanner quality parity:** AI generative image inpainting, fully automatic
accurate OCR text replacement on arbitrary photo backgrounds, Bengali OCR word
bounding boxes, PDF lock/password, digital signatures, Office conversions,
and direct editing of imported native PDFs remain unimplemented. Image text
replacement uses local background interpolation (not a generative model), which
can leave visible artifacts on patterned backgrounds. Tools which are not ready
still say so. All changes require real Android device testing in addition to CI.

## Requirements

- Flutter **3.47.4** (Dart 3.13.3)
- Android SDK and Java 17
- Android min SDK 24, compile with the SDK Flutter selects

## First checkout / run

```bash
git clone https://github.com/faria2177/DS-Fult.git
cd DS-Fult
bash tool/setup_android.sh
bash tool/download_ocr_models.sh
flutter pub get
bash tool/patch_tesseract_gradle.sh
flutter analyze
flutter test
flutter run
```

The first setup uses `flutter create` to generate the official version-matched `android/` host template; CI generates it on each build.
`tool/download_ocr_models.sh` fetches the official Bengali Tesseract
traineddata into Flutter assets **before** building. It is packaged in the
APK and does not download again during normal app use. The traineddata binary
is not committed to Git. Camera/ML Kit/Tesseract functionality requires
physical Android device testing. No document images are sent to cloud AI.
`tool/patch_tesseract_gradle.sh` removes a legacy Gradle repository block
from the locally downloaded OCR plugin because the published plugin still
references `jcenter()`; CI runs this automatically.

## APK downloads

Open the repository's **Actions → Android APK → latest successful run → Artifacts → DocScanner-Android-APKs**. Release APK files will be in that ZIP after the workflow has succeeded.

## Architecture

```text
lib/main.dart
  src/app.dart                 App, theme preferences
  src/screens/home_shell.dart  Home / Files / Tools / Me
  src/screens/camera_screen.dart  Camera + gallery picker
  src/screens/manual_camera_screen.dart Manual capture fallback
  src/screens/id_card_screen.dart Front / back capture
  src/screens/crop_screen.dart Four-corner crop editor
  src/screens/document_screen.dart Page editing / exports
  src/screens/edit_text_screen.dart OCR + editable text
  src/screens/image_text_editor_screen.dart Direct visual text edit / erase
  src/screens/pdf_tools_screen.dart Page organizer / merge / PDF tools
  src/services/image_processor.dart Image filters / perspective
  src/services/document_edges.dart Native contour detection / gallery auto-crop
  src/services/image_text_processor.dart Pixel-level text replacement
  src/services/document_export.dart PDF/print/share
  src/storage/document_store.dart Local image+JSON library
```

The full-resolution original image is kept separate from processed copies; the OCR text is stored in the local document index. The first release keeps deleted image files for potential recovery, so future storage cleanup must be implemented separately.

Developed for **DC / DS** by Md Jahidul Islam.
