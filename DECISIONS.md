# DocScanner — Architecture Decision Records (ADRs)

**Last reviewed:** 2026-11-09. These decisions summarize current implementation and user-confirmed constraints. A new decision should include date, context, choice, consequences, alternatives and affected code; do not silently reverse an accepted decision.

## ADR-001 — Flutter UI, Android-native scanner

**Status:** Accepted  
**Decision:** The application interface and document workflows use Flutter/Dart. Live detection, camera capture and selected platform functions use a locally patched `third_party/doclens` plugin and Android-native implementation.  
**Why:** Allows a flexible Flutter UI while retaining native camera/detection performance.  
**Consequences:** Native changes require Kotlin/Gradle regression tests and real-device checks; a working native engine must not be replaced purely for UI imitation.  
**Related:** `lib/src/screens/camera_screen.dart`, `third_party/doclens/`.

## ADR-002 — Local-first, no cloud or Ask AI

**Status:** Accepted  
**Decision:** Store images, index and settings locally; no cloud account/sync/AI-chat surface. Do not include **Ask AI** or paywall controls. The app may invoke Android sharing or externally installed apps when the user selects an action.  
**Why:** User preference for an offline scanner, privacy and predictable operation.  
**Consequences:** A real public share link or cross-device sync cannot be promised without a separately authorized service.  
**Related:** `document_store.dart`, `document_export.dart`, `home_shell.dart`.

## ADR-003 — Manual shutter and reversible editing

**Status:** Accepted  
**Decision:** Automatic capture is disabled by default, including card mode. Manual shutter, edge preview, four-corner crop, rotate, Compare and explicit Done/Save remain available. Keep original page data when possible.  
**Why:** The user repeatedly reported unstable auto-capture and wrong crops.  
**Consequences:** Scanning requires a user tap; uncertain detectors must fall back to manual review.  
**Related:** `camera_screen.dart`, `crop_screen.dart`, `image_processor.dart`.

## ADR-004 — Avoid CameraX rebind on mode-only changes

**Status:** Accepted  
**Decision:** Single ↔ Batch and Scan ↔ ID Cards chooser normally change Flutter state without recreating CameraX. Rebind only when native configuration actually differs; release one camera owner before a separate camera or external picker takes ownership.  
**Why:** Prevent reflection/mirroring, black placeholder flashes and duplicate camera-session races.  
**Tradeoff:** Certain warp/configuration switches still incur controlled restart.  
**Related:** `CameraScreen.captureConfigKey`, `DoclensScreen`, regression tests.

## ADR-005 — One A4 image per saved two-sided card

**Status:** Accepted in `0.5.10`  
**Decision:** ID Card, Driver License and Bank Card capture Front/Back in one camera session and combine them onto one white A4 JPEG. Mark new documents `compositeCardPages=true`; export one A4 PDF page for each combined sheet. General template remains multi-page with separate images.  
**Why:** Matches demonstrated review/document page counts and simplifies sharing.  
**Consequences:** The rendered sheet is saved; individual side metadata does not yet survive as independently editable sources. See TODO T-101.  
**Compatibility:** Legacy two-image card documents retain the old PDF composition branch.  
**Related:** `id_card_screen.dart`, `id_card_page_composer.dart`, `document_export.dart`, `models.dart`.

## ADR-006 — One persistent Scan settings source

**Status:** Accepted  
**Decision:** `Me → Scan` and the camera's `⋮ → More Settings` open the same seven-setting interface, backed by a single persisted settings record.  
**Why:** Avoid mismatched toggles and inconsistent scanning behavior.  
**Consequences:** Settings that affect native configuration must use a controlled rebind; UI-only changes should not.  
**Related:** `scan_more_settings_screen.dart`, `scan_settings_store.dart`.

## ADR-007 — Tools-grid cleanup is a UI scope decision

**Status:** Accepted  
**Decision:** Remove **Mega Scan, Long Document, Driver License, Bank Card, Photo Translation, Scan Code, To PPT, Erase Marks, Restore Photo** from the Tools grid as requested. In `0.5.16`, also remove **Edit Text** and **Split PDF** tiles only; retain document-level Edit Text and other PDF workflows. Code or entry points elsewhere may remain if useful; not every internal implementation is a visible Tools item.
**Why:** User-defined navigation structure; reduces clutter without destructively removing working services.  
**Consequences:** Avoid reintroducing these grid entries without a new requirement.  
**Related:** `home_shell.dart`, `README.md` v0.5.2.

## ADR-008 — Offline Office generation, with stated fidelity limits

**Status:** Accepted as current implementation  
**Decision:** Word and Excel are generated from offline OCR text; PowerPoint contains page-image slides. PDF is generated locally from page images.  
**Why:** Real, shareable files without a cloud converter.  
**Consequences:** Native PDF editability, original typography, table boundaries and slide objects are not guaranteed to be reconstructed. Do not market it as lossless conversion.  
**Related:** `docx_export.dart`, `xlsx_export.dart`, `pptx_export.dart`, `document_export.dart`.

## ADR-009 — An app access PIN is not file encryption

**Status:** Accepted / Security limitation documented  
**Decision:** Use the existing per-document PIN hash to restrict app UI operations; keep the limitation visible.  
**Why:** It supports the current local lock UI but does not encrypt exported PDF, page images or data at rest.  
**Consequences:** Never describe the Lock feature as cryptographic PDF encryption. Any upgrade requires a new security design, migration plan and tests.  
**Related:** `lock_document_screen.dart`, `document_store.dart`.

## ADR-010 — CI generates the Android host at build time

**Status:** Accepted  
**Decision:** Run `tool/setup_android.sh` on a fresh checkout, download the Bengali OCR model before bundling, and patch the legacy Tesseract plugin Gradle script locally. GitHub Actions then runs native tests, Flutter analysis/tests and ABI-split APK builds.  
**Why:** Keep the Flutter/Gradle template consistent with pinned Flutter and avoid committing generated or downloaded dependency artifacts.  
**Consequences:** A fresh local build must follow the documented setup order. If dependency sources change or fail to download, CI may fail even when Dart code is unchanged.  
**Related:** `.github/workflows/android-apk.yml`, `tool/`.

## ADR-011 — Offline still-image Auto Crop combines independent boundary evidence

**Status:** Accepted for `0.5.13` candidate; device quality requires verification.
**Decision:** Retain fast real-time OpenCV detection. After a manual shutter/import, additionally search beyond the strongest text/table contour using deeper still-image candidates, geometric paper preferences and a page-versus-background colour mask. Promote an outer-mask region over an existing crop only when it is a credible, substantially larger paper quadrilateral. Preserve the original upright image and require manual corner adjustment if confidence or framing is uncertain. ID Card selection stays separate.
**Why:** Thin/low-contrast outside page edges can lose to printed inner boxes in captured high-resolution stills, especially on neutral desktops. Independent colour and geometry cues increase full-sheet recall without depending on CamScanner proprietary code or cloud processing.
**Consequences:** Hard scenes may need an additional still-only processing pass, and no camera-independent confidence threshold can guarantee accurate corners. Regressions must be tested on device for false page/background selection, latency and preserved text.
**Alternatives:** Always applying the most recent live quad (rejected due preview/still crop mismatch); always promoting the largest rectangle (rejected due desktop/background false positives); proprietary scanner binaries or online APIs (excluded).
**Related:** `DocumentBoundaryDetector.kt`, `StillCapturePagePreference.kt`, `QuadDetector.kt`, `ScannerSession.kt` and native regression tests.

## ADR-012 — Live box rejection and mint tint are separate concerns

**Status:** Accepted for `0.5.15`; device tuning pending.
**Decision:** A suppressed live quad must remain suppressed through the Flutter controller; do not restore a raw native proposal when smoothing returns null. For normal Scan (not ID Card), compare independent low-resolution colour-connected and OpenCV candidates every analyzed frame, rejecting near-camera-border rectangles when they lack credible whole-page evidence. Require additional temporal confirmation before a sudden large edge-hugging box replaces the tracked page. Paint a faint green fill **only inside the accepted quad**, keeping its appearance independent of the detection status label.
**Why:** Video `381536.mp4` captures a moving, chair-backed textile whose border repeatedly jumps to the entire camera frame. The green tint communicates the selected region but cannot improve the native detection calculation by itself.
**Consequences:** More colour-mask work on normal live frames may affect FPS/battery; rejecting very close-to-frame bounds may require the user to move the phone back. Preserve manual capture and the separate ID Card path; measure actual accuracy/latency on the target device.
**Related:** `OpenCvBoundaryAdapter.kt`, `LiveBoundarySelector.kt`, `quad_smoother.dart`, `controller.dart`, `doclens_screen.dart`.

## ADR-013 — On-device photo tools with explicit editing quality limits

**Status:** Accepted for `0.5.16`, device testing pending.
**Decision:** Keep Passport Photo Maker, BG Remover and Image Resizer fully offline, with local gallery/camera/DocScanner input and explicit Preview → Save as New or Share. Passport sizes use 300 DPI and a 4×6 inch printable layout; resizer supports custom exact pixels and JPG/PNG. Background removal uses an edge-connected solid-colour tolerance mask, with no claim of face/person AI segmentation. Preserve originals.
**Why:** Replaces two nonfunctional Tools placeholders and a limited resize dialog without adding cloud services, proprietary models, hidden payment requirements or risky automatic overwrites.
**Consequences:** Rough boundaries on detailed hair or patterned backgrounds and country-specific passport acceptance checks remain outside the current implementation. An AI segmenter or larger offline model would require separate quality, license and APK-size evaluation.
**Related:** `home_shell.dart`, `photo_studio_screen.dart`, `photo_studio_operations.dart` and new photo-tool tests.

## ADR-014 — Extract Text and Edit Text are separate destinations

**Status:** Accepted for `0.5.17`; physical-device verification pending.
**Decision:** The Tools `Extract Text` entry and Home Quick OCR should select or import a source image/document and open a dedicated editable transcript directly. Keep the removed Tools-grid `Edit Text` tile absent while preserving document-level image-text editing. Explicit English/Bengali selection forces recognition in that language; exporting to Word must use the user's corrected transcript rather than re-running OCR. No autosave or cloud upload occurs.
**Why:** Video `381563.mp4` demonstrates OCR-to-text, copy and Word export, and the old action redirected users to an Edit Text menu entry instead of performing that workflow.
**Consequences:** Users choose explicit Copy, Share Text or To Word; native OCR still requires device testing. Reloading the source intentionally re-recognizes it; unsaved edits remain local to the current editor screen until exported.
**Related:** `extract_text_screen.dart`, `home_shell.dart`, `docx_export.dart` and tests.

## ADR-015 — Preview long images before a requested export

**Status:** Accepted for `0.5.18`; CI/device verification pending.
**Decision:** Keep existing direct long-image sharing from document-level menus, but make Tools → PDF to Long Image a separate source-picker and scrollable preview/editor flow. Use the same offline stitching engine with an optional, content-safe footer watermark. Provide explicit Save as New (no overwrite), Share Long Image, Share as Images (original separate source pages), Save to Gallery (Android MediaStore), and Share as PDF (continuation split into readable A4 pages). Do not present image-backed document input as arbitrary binary PDF import.
**Why:** Video `381562.mp4` shows a preview and distinct save/share actions; instantly opening Share from Tools hid the content and omitted important decisions.
**Consequences:** More decoded image memory for previews and PDF pagination; existing 15,500px safety cap remains. Validate MediaStore, tall receipts, source preservation and share receivers on device.
**Related:** `long_image_studio_screen.dart`, `image_tool_operations.dart`, `document_export.dart`, `home_shell.dart` and tests.

## ADR-016 — Device PDF import is offline rasterization for image export

**Status:** Accepted for `0.5.19`; CI and device verification pending.
**Decision:** Tools → PDF to Images opens the existing source-picker with a new Android document-PDF option. Use the platform Storage Access Framework to read a user-selected PDF into app cache without requesting broad media access. Rasterize locally through the installed `printing` PDF backend, import image pages into local DocScanner storage, and expose a preview/select/export screen with explicit JPG/PNG, Save as New, Share Images and Gallery actions. Bound initial conversion to 80 MB and 80 pages to control resource use. Preserve originals; do not imply image exports are editable vector PDFs.
**Why:** Reference `381560.mp4` shows opening a PDF and viewing its pages before image export; the previous tool only shared already stored image pages.
**Consequences:** Android picker lifecycle and PDFium failures require device testing, cached source copies and raster staging must be removed, and converted pages consume local storage. Imported password-protected or very large documents can fail with an actionable error. OCR text and vector graphics are not reconstructed.
**Related:** `DoclensPlugin.kt`, `pdf_import_service.dart`, `pdf_to_images_screen.dart`, `pdf_image_export.dart`, `video_tool_source_picker.dart` and tests.

## ADR-017 — Extract selected pages into a new image-backed document

**Status:** Accepted for `0.5.20`; CI and Android UI verification pending.
**Decision:** Tools → Extract PDF Pages should select an unlocked existing/Android-imported PDF document, display visual page thumbnails with checkboxes and Select All, then create a distinct local DocScanner document containing only selected pages in their original order. Use the same screen from PDF Tools instead of a second, text-only selection dialog. Do not remove or overwrite source pages automatically.
**Why:** Video `381564.mp4` shows a document picker, page checkboxes, explicit extract confirmation and a resulting document preview; the older UI hid this within an unrelated PDF Tools screen.
**Consequences:** A real PDF is rasterized before this extraction using ADR-016, so editable PDF text/vector structure is not preserved. Thumbnail scrolling and extract/save navigation need physical Android 16 checks.
**Related:** `extract_pdf_pages_screen.dart`, `home_shell.dart`, `pdf_tools_screen.dart`, `document_store.dart` and widget tests.

## ADR-018 — Stage page rotation and persist one document update

**Status:** Accepted for `0.5.21`; Android device acceptance pending.
**Decision:** Tools → Rotate PDF and PDF Tools → Rotate Pages lead to the same multi-select, image-backed page preview. Left/Right/180°/Reset operate solely on staged quarter-turns; Cancel/Back discard them. Done transforms only net-changed pages, retains original capture paths and unchanged page IDs/order, and replaces the complete list of changed page records in a single index persist. Prepared page images are written separately to avoid overwriting the prior versions. Preserve PNG alpha rather than flattening transparency to JPEG.
**Why:** Video `381565.mp4` shows visual selection, direction controls and a confirmation phase; the former Tools route only opened the document viewer. Batch saving prevents partially applied page rotations when decoding fails midway.
**Consequences:** Original file paths stay available for recovery, which can increase local storage; interrupted index writes retain the existing K-009 risk. Large rotated pages may take time, and imported PDFs are rasterized first. UI and export orientation require on-device review.
**Related:** `rotate_pages_screen.dart`, `document_store.dart`, `image_processor.dart`, `home_shell.dart`, `pdf_tools_screen.dart`, page-rotation tests.

## ADR-019 — Import File uses existing offline PDF and gallery pipelines

**Status:** Accepted for `0.5.22`, device test pending.
**Decision:** Tools → Import File offers Android PDF SAF selection and image-gallery selection in an import-only source sheet. Save imported pages in local DocScanner storage and open the result. Do not show previously saved documents as possible imports. Reuse the already-tested PDF rasterizer and its size/page safeguards rather than introducing a second file permission or parser implementation.
**Why:** The old Tools entry was a visible placeholder, while an appropriate offline PDF/image import workflow already existed behind PDF to Images. One shared path reduces inconsistent file cleanup and permission handling.
**Consequences:** PDF vector text and fonts are not preserved; the import is a local image-backed document. DOCX/PPTX are not supported in this flow. Native SAF intent, cancellation, large files and file readability need Android 16 verification.
**Related:** `home_shell.dart`, `video_tool_source_picker.dart`, `pdf_import_service.dart`, picker widget tests.

## ADR-020 — Image to PDF writes only to explicitly chosen destinations

**Status:** Accepted for `0.5.23`; CI and device acceptance pending.
**Decision:** Tools → Image to PDF selects/gallery-imports pictures, stages selected-page order and builds an independent image-backed A4 PDF via the existing offline exporter. Use an inline PDF viewer for preview, Android `ACTION_CREATE_DOCUMENT` for a real user-chosen PDF save destination, and Android share targets for sharing. The native Save As bridge accepts only PDFs produced in DocScanner app cache and copies the bytes to the explicitly selected `content://` URI; cancellation is a non-save. Do not overwrite original images or add broad storage permissions.
**Why:** The previous Tools action imported images but never produced the requested PDF. A cache-only PDF is not a durable saved document, so the explicit SAF destination is needed to satisfy Save PDF.
**Consequences:** Imported/source photos remain in the DocScanner image-backed library; a saved PDF is a separate external file, not editable vector text. Android providers, PDF viewer, high-page-count memory and sharing receivers need real-device verification. No encryption or cloud hosting is implied.
**Related:** `image_to_pdf_screen.dart`, `document_export.dart`, `pdf_file_delivery.dart`, `DoclensPlugin.kt` and widget tests.

## ADR-021 — Preserve overlay continuity while confirming border challengers

**Status:** Accepted for `0.5.24`; physical camera comparison pending.
**Decision:** The Single/Batch scanner should render a barely tinted green interior within an already accepted quad, separately from edge classification. In the Dart `QuadSmoother`, an invalid or missing observation terminates the run of incompatible contenders. A coherent challenger awaiting the stricter near-border confirmation should not make the current quad disappear due to the shorter generic lost-target timeout; wildly inconsistent alternatives may still hide it. Preserve the manual shutter, old still-image crop preference and current native OpenCV detector.
**Why:** The camera previously passed the outline-only style even though a filled style existed. With the default six-frame mismatch hide limit and eight-frame frame-edge challenger confirmation, a continuous valid candidate could cause a two-frame green-box blink. Adjacent nulls also allowed separated false positives to accumulate toward an artificial disappearance.
**Consequences:** A coherent new document can keep the previous box visible slightly longer before an intentional switch; this is a temporal UI tradeoff and does not prove correct recognition of a fabric-versus-chair boundary. The green overlay is visual feedback, not an input mask or a reliability boost to the detector. Verify actual device positioning, low-light behavior and CPU/FPS before claiming improved scan accuracy.
**Related:** `quad_smoother.dart`, `quad_overlay.dart`, `camera_screen.dart`, `quad_smoother_test.dart`, `BUGS.md` B-011.

## ADR-022 — Review OCR and local PDF edits before explicit export

**Status:** Accepted for `0.5.26`; Android hardware and Office-file fidelity checks pending.
**Decision:** Tools → Edit PDF and Sign should use page-specific, actually implemented offline editing actions. Tools → To Word and To Excel should first let users choose app, photo, PDF or scan sources, select pages and OCR language, then inspect/edit recognized text before creating the genuine DOCX/XLSX and opening the share sheet. The Excel table preview and exporter must agree on inferred column delimiters. Do not silently overwrite source document pages with OCR corrections or use cloud conversion.
**Why:** A bare file chooser + blocking spinner + immediate share gave users no chance to review OCR errors, column structure or page selection. Sign and Edit PDF lacked a consolidated professional editing surface.
**Consequences:** Text and table reconstruction remain limited by offline OCR and whitespace heuristics. Image-backed PDF edits do not keep vector/source text layers; drawn electronic signatures do not add certificate cryptography. UI accuracy, Android share destinations, OCR performance and Excel/Word fidelity need real-device acceptance.
**Related:** `home_shell.dart`, `office_conversion_screen.dart`, `pdf_tools_screen.dart`, `signature_screen.dart`, `video_tool_source_picker.dart`, `docx_export.dart`, `xlsx_export.dart` and `office_conversion_workflow_test.dart`.

## ADR-023 — Video-inspired DS Word workflow remains local and honest

**Status:** Accepted for `0.5.27`; Android screenshot/receiver verification pending.

The `381709.mp4` CamScanner reference informs the DS AI banner, transition indicator, white-page editable Word preview, local formatting and sharing sheets. Original Flutter widgets, not proprietary assets/code, implement the appearance. On-device OCR and real DOCX generation preserve edited text. DS Writing is clearly rule-based cleanup, no cloud or generative AI. Unsupported non-Latin text-to-PDF is rejected rather than silently dropping glyphs. Original scanned images remain unchanged by Word edits.

## ADR-024 — Excel reference uses an editable offline grid with explicit fidelity limits

**Status:** Accepted for `0.5.28`; Android handset verification pending.
**Decision:** `381711.mp4` informs a DS-branded To Excel source picker, offline OCR progress, interactive sheet grid and prepared XLSX export panel. Users can correct cells or the complete tab-separated sheet, undo edits, choose table-only rows and change cell dimensions/font weight. XLSX OpenXML stores those formatting choices and edited values.
**Why:** The former Excel workflow exposed raw OCR text and a small table preview, lacking the video-style spreadsheet interaction.
**Consequences:** OCR text splitting alone cannot reconstruct arbitrary merged cells, ruled table geometry, colours or complex formatting. The interactive grid renders at most 85 rows and 14 columns for mobile performance, while full-sheet text editing and XLSX export retain the complete content. Save as PDF currently rejects unsupported Unicode instead of outputting corrupt glyphs. No cloud or proprietary code/assets are introduced.
**Related:** `excel_review_screen.dart`, `office_conversion_screen.dart`, `xlsx_export.dart`, `test/excel_review_screen_test.dart`.

## How to change a decision

For a meaningful reversal, append a new `ADR-011+` entry with the proposed alternative, user approval when scope changes, migration/backward-compatibility behavior, tests and rollback. Mark the old ADR `Superseded by ADR-XXX`; preserve the historical rationale.
