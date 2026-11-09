# DocScanner — Progress Snapshot

**Last documented:** 2026-11-09
**Current candidate release:** `0.5.30+44`
**Last fully successful CI baseline before this patch:** [GitHub Actions run #42660360758](https://github.com/faria2177/DS-Fult/actions/runs/42660360758)
**Baseline commit:** [`ee9d3e6`](https://github.com/faria2177/DS-Fult/commit/ee9d3e6dd5a41df1797a83dff38e1703cd77c798)

> These are code/CI milestones, **not** proof that every reference video has been matched pixel-for-pixel or validated on a real Android handset. Always check the latest `main` commit before continuing.

## Status legend

- **Implemented / CI-tested:** Code and relevant automated checks exist.
- **Implemented / device-check needed:** Code exists; hardware behavior remains to be verified.
- **Limited:** Functional approximation, with explicit quality or capability gaps.
- **Planned:** Tracked in [TODO.md](TODO.md), not yet complete.

## Milestones

| Version | Delivered work | Current assessment |
| --- | --- | --- |
| `0.3.7`–`0.4.0` | Native border tracking, manual capture, crop, scan settings/effects, HD | Implemented; device tuning ongoing |
| `0.5.0` | Six-template ID Cards chooser | Implemented; device-check needed |
| `0.5.1` | Avoided CameraX rebind for default Single/Batch and Scan/ID Cards UI-only switching | Implemented; regression test + device-check needed |
| `0.5.2` | Shared `Me → Scan` and camera More Settings; removed nine Tools-grid items | Implemented / CI-tested |
| `0.5.3` | Document grid, page editor, More menu, local sharing tools | Implemented; reference matching limited by device |
| `0.5.4`–`0.5.5` | Watermark/brush editing, Files multi-select, sorting, folders, merge, long image | Implemented / CI-tested; device-check needed |
| `0.5.6` | Colour/background-assisted crop fallback | Native tests added; difficult scenes remain a risk |
| `0.5.7`–`0.5.8` | More video-style Tools screens; watermark, reorder, compress, lock and Smart Erase UI | Implemented with documented non-AI limitations |
| `0.5.9` | Still-image detector prefers complete visible A4 sheet over a strong inner table when evidence supports it | Native regression tests passed; field check needed |
| `0.5.10` | Same-session Front→Back capture, General multi-page mode, A4 composite ID review/save/PDF, add paired pages | Implemented / native + Flutter CI passed; field check needed |
| `0.5.11` | Card-specific OpenCV quad ranking, source-image re-crop recovery, improved true-size A4 card layout | Implemented / CI-tested; physical device verification pending |
| `0.5.12` | Single Scan crop guard against internal horizontal text bands; recent credible live outline seeds manual review, full original preserved; Adjust corners actions respect navigation safe-area | Native/Flutter CI passed in run #42458973854; device verification pending |
| `0.5.13` | More capable still-image Auto Crop: background-versus-paper contrast mask, thorough still-only edge/line candidate search and safer outer-page preference | Regression tests added; CI/device verification pending |
| Post-`0.5.13` | Video `381526.mp4` regression: try still-only saturated outer-panel recovery on mixed backgrounds; reject small, centred inner title/label quads in either JPEG orientation; retain full-original review if uncertain | Code + synthetic native regressions added; CI and physical-device verification pending |
| `0.5.14` | Video `381530.mp4`: prefer a coherent coloured document over an elongated chair-frame false detection, adaptive jitter damping with stronger switch confirmation, reset tracking after camera lifecycle changes, remove permanent preview border | Kotlin/Dart tests and complete GitHub CI passed in #42486007998; physical-camera confirmation pending |
| `0.5.15` | Video `381536.mp4`: fix controller's raw-quad fallback that resurrected rejected detections; reject camera-border contenders, delay abrupt border takeovers, add tiny-motion deadband and persistent pale-green fill inside accepted quad | Native/Flutter CI passed in #42488745515; physical-device confirmation pending |
| `0.5.16` | Three functional on-device image tools: Passport Photo Maker (standard sizes, positioning, background colours, 4×6 print sheets), BG Remover (uniform-background flood fill, transparent/coloured PNG), Image Resizer (custom dimensions, ratio lock, quality and format); removed Edit Text and Split PDF from Tools only | Unit/widget regressions added; CI and real-photo verification pending |
| `0.5.17` | The `381563.mp4` Extract Text follow-up: Tools/Quick OCR now uses the video-style document/gallery/scan source picker and opens a dedicated editable text screen directly. English/Latin and Bengali can be re-recognized separately, with Copy, Select All, Word and text sharing; document-image Edit Text remains distinct. | New widget tests and Word-content test; CI/device verification pending |
| `0.5.18` | `381562.mp4` PDF to Long Image workflow: source/gallery picker, scrollable stitched preview, optional watermark footer, Save as New, Share Image, Share as PDF, Share as Images and Save to Gallery. Very tall PDF exports are paginated onto readable A4 sheets. | Synthetic image/PDF and screen tests added; CI and Android Gallery/share verification pending |
| `0.5.19` | `381560.mp4` PDF to Images: Android Storage Access Framework PDF picker, offline PDF rasterization into image-backed pages, selected-page preview, JPG/PNG export, Save as New/Share/Save to Gallery. Existing document pages also work. | Dart selection and transcode tests; native picker and physical-device verification pending |
| `0.5.20` | `381564.mp4` Extract PDF Pages: direct source/gallery/PDF selection, page preview and checkboxes, select all/clear all, Extract as New Document with opened result. Existing PDF Tools extract action also routes to the same screen. | Widget tests for selective extraction/order and original preservation; CI and Android UI verification pending |
| `0.5.21` | `381565.mp4` Rotate Pages: Tools/PDF Tools source → multi-select page thumbnails → 90° left/right, 180°, reset, zoom preview → explicit Done to update only changed pages and open document. Rotation preserves original image paths and PNG transparency. | Staging/undo widget tests, asymmetric image-orientation and transparent PNG tests; fresh CI and device verification pending |
| `0.5.22` | Tools → Import File now offers device PDF and images rather than a placeholder toast. The imported pages are saved locally and the result opens in document preview. | UI/native-picker cancellation regression added; CI pending, physical Android SAF and large PDF tests remain |
| `0.5.23` | Tools → Image to PDF now selects/gallery-imports photos, selects and reorders pages, previews an actual multi-page A4 PDF, supports editable output name, Save PDF via Android SAF and Share PDF. | UI selection/order/export tests and file-name tests added; CI and Android Save As integration pending |
| `0.5.24` | Live green quad stability follow-up: faint green fill is actually enabled on the Single/Batch camera; identity smoother resets outlier streaks after missing frames and prevents a coherent delayed border challenger from making the box blink before confirmation. | Two synthetic regression tests added; CI and HONOR Android 16 video/CPU acceptance pending |
| `0.5.25` | Scan/Batch filled green four-corner border increased from 2.5 to 3.5 logical pixels, retaining the delicate mint interior, manual shutter and existing tracking. | Constructor regression test added; APK/real-camera visual verification pending |
| `0.5.26` | CamScanner-style tool workflows: Edit PDF page chooser with working edit/sign/watermark/rotate/reorder/extract/compress/print/share actions; Sign UI adds ink palette and pen-size controls; To Word/To Excel use PDF/gallery/app source picker, page selection, offline OCR, editable review, real DOCX/XLSX export and Share. | New widget and table-parsing tests added; GitHub CI and physical Android device review pending |
| `0.5.27` | `381709.mp4` DS visual identity: pastel DS AI Tools banner, dark four-column categories, two-column To Word Scan/Gallery/Device source picker, local `Converting with DS AI` indicator, white-page To Word review with tap-to-edit, undo/redo, page switching, DS Formatting persisted into DOCX, rule-based DS Writing, Word/PDF/original-image sharing, and CS PDF → DS PDF. | Widget regressions added; CI/device pixel comparison pending; Unicode text-PDF limited |
| `0.5.28` | `381711.mp4` To Excel: DS-branded X badge and two-column picker, `Converting with DS AI` offline recognition, spreadsheet-style column letters/row numbers, pinch/pan, per-cell edits, sheet-text edits, undo/redo, multi-sheet navigation, Only tables/All content filtering, DS Formatting persisted to XLSX column width/row height/font/bold first row, genuine XLSX export sheet and editable share; PDF export of Latin-script table cells. | UI + XLSX structure regressions added; CI pending; real-device parity and table reconstruction accuracy need testing |
| `0.5.29` | Me → AI Mode: add Google AI Studio, Groq Cloud, OpenRouter and nine other optional provider credential slots; encrypt secrets with OS secure storage; choose active provider and opt in via Enable toggle; remove/replace keys. Android Back from the root shell now asks to Cancel/Exit. | Configuration and exit-dialog widget tests added; GitHub CI / Android 16 validation pending. **No AI inference calls or automatic scan uploads in this release.** |
| `0.5.30` | Explicit opt-in text AI: use saved Gemini/Groq/OpenRouter keys for proofreading one Word or Extract Text page and cleaning one Excel sheet. Display provider/model/character count and text preview before external send; show AI suggestion for Apply/Discard. Preserve Word/Excel Undo and original scanned images. | HTTP adapters, consent UI and mocked-request regressions added. No automatic uploads or silent fallbacks. CI + live credential/device testing pending. |

### 0.5.30 — Text AI proofread with per-request approval

- Added separate HTTPS text-generation adapters for Gemini `generateContent`, Groq chat completions and OpenRouter chat completions, with provider-specific headers and fixed endpoints. Actual keys are read from encrypted storage only after the user approves one bounded text request (up to 12,000 characters). Other nine API entries remain secure setup-only slots.
- DS Writing → AI Proofread sends only the current Word page's editable OCR text. To Excel → AI clean sheet (toolbar) submits only the current sheet's editable tab-separated text. Tools → Extract Text has its own opt-in AI Proofread button. No source image, file path or other page is transmitted.
- A clear send approval dialog shows provider, model ID, character count, privacy/billing caveat and a text preview. AI suggestions are always shown before Apply/Discard; Word and Excel keep reversible Undo history and originals untouched. Model ID is customizable in Me → AI Mode.
- Responses use size/time bounds, HTTPS host allowlisting, no redirects and generic safe error messages. Credentials and OCR text are never logged. Android release manifest gains INTERNET permission only to support the user-approved requests.
- Unit and widget tests cover disabled-mode no-network behavior, three provider request formats, rejection of stale/oversized requests, consent cancellation, preview, application and undo. Actual APIs, rate limits, prices, model availability and privacy requirements must be checked on the user's Android device.

### 0.5.29 — Optional AI credentials and exit confirmation

- Me contains AI Mode, with 12 categorized provider entries, links to their official key dashboards, a masked API-key editor, Cloudflare Account ID, explicit key replacement and deletion, active-provider selector, and a separate Enable toggle.
- The provider ID and on/off selection are ordinary local preferences; **API keys and Cloudflare Account ID are stored only in Android Keystore-backed encrypted storage** (`flutter_secure_storage`), never in `SharedPreferences` or document JSON. No secrets are printed or synced by DocScanner.
- Enabling AI Mode is currently only a saved preference. No scan, image, extracted text, or metadata is transmitted; provider-specific AI requests require a future opt-in integration and transparent usage/billing information. A provider's free tier may change and is never unlimited.
- The root Back action opens a Cancel / Exit dialog. Confirmed exit invokes Android's app-close navigation command; no “saved” notification is shown.
- Widget tests use a fake key vault and cover mandatory providers, obscured input, preferences separation, key removal, Cloudflare Account ID, Me navigation and exit confirmation. Check actual encrypted-storage behavior and exit handling on HONOR VKP-NX9 before declaring device-level verification.

## Verified in the 0.5.10 CI run

- [x] Android host project can be generated in CI.
- [x] OCR model bundling/build setup steps completed.
- [x] Native detector unit tests passed.
- [x] `flutter analyze` passed.
- [x] `flutter test` passed, including new card-layout/model tests.
- [x] Release APKs built with `--split-per-abi` and uploaded as `DocScanner-Android-APKs`.
- [ ] Real HONOR VKP-NX9 (Android 16) end-to-end camera/UI verification — no verified outcome recorded.
- [ ] Pixel-by-pixel reference-video comparison on target handset — no verified outcome recorded.

## Feature readiness

| Capability | Current state | Evidence / next check |
| --- | --- | --- |
| Multi-page scan and Files library | Implemented | Test add/reorder/delete on physical device |
| Manual 4-corner crop, rotate, filter | Implemented | Check preserving document edges and orientation |
| Two-sided ID on one A4 image / PDF | Implemented, CI-tested | Check scan/import → Front → Back → crop → one-page export |
| OCR (Latin + Bengali) | Implemented, language/lighting limited | Validate legible NID/receipt examples offline |
| PDF/image share and print | Implemented | Verify receivers and Android permissions |
| DOCX/XLSX/PPTX export | Implemented with conversion limits | Open output in office viewers; compare fidelity |
| Smart Erase | Local pixel processing | Complex backgrounds can show artifacts |
| Passport / Background / Resize tools | Local image processing and Save as New/Share | Check head framing, uniform/uneven backgrounds, large images and precise print dimensions on phone |
| Password protection | App UI access PIN | Does not encrypt PDFs/files |
| Cloud, Ask AI | Intentionally absent | Do not add without explicit new scope |

## Next milestone definition

The next release should close **at least one P0 task** in [TODO.md](TODO.md) with reproducible before/after evidence from the real device. Each code change needs `flutter analyze`, `flutter test`, relevant native tests and an APK build. Update this file, the issues register and the release version only after validation.

### 0.5.26 — Four professional Tools workflows

- **Tools → Edit PDF** now accepts app documents, imported images and locally rasterized PDF files; shows a selectable-page strip and grouped editing/organizing/export controls. Every action routes into an existing implementation. Imported PDF vector fonts and selectable text are not preserved by editing; the app operates on image-backed pages.
- **Tools → Sign** uses the shared source picker, then a dark signing canvas with page preview, black/blue/red/green ink, adjustable stroke size, Undo/Clear and explicit Apply Signature. This is a visible image signature applied to a page, not an encrypted/certificate-backed PDF signature.
- **Tools → To Word / To Excel** now uses Scan/Gallery/PDF/app source selection, toggles which pages to convert, selects English/Latin versus Bengali offline OCR, and previews/edit recognized page text before sharing genuine `.docx`/`.xlsx` files. Excel's table preview uses the same tab/double-space column splitting as its exporter. Edited OCR text is exported without re-running OCR; source image pages are not overwritten.
- Full original CamScanner layout, table cells, embedded graphics, handwriting, font/paragraph positioning, and merged Excel headings are **not** guaranteed to match scanned originals. That requires document layout understanding beyond local text-only OCR. No cloud or proprietary CamScanner processing was added.
- After repeated CI HTTP 504 failures downloading Gradle's bulky `-all.zip` from redirected GitHub release assets, `tool/setup_android.sh` now directs the generated wrapper to Gradle's official `downloads.gradle.org` `-bin.zip` archive. This changes CI distribution retrieval only, not the native detector or app behavior.

### 0.5.25 — More visible green document frame

- The filled green four-corner border in Single/Batch mode is now 3.5 logical pixels wide instead of 2.5. Other overlay presets and the low-alpha interior fill remain unchanged.
- This is visual styling only; it neither affects document detection nor claims pixel-perfect equivalence with CamScanner. Check the rendered border on HONOR Android 16 in bright and dim environments.

### 0.5.24 — Live quad jitter/blink follow-up

- `camera_screen.dart` still requested `QuadOverlayStyle.outline` even though the user had asked for a pale green accepted-quad interior in the Scan preview. Normal Scan/Batch now uses the filled outline style with a very low alpha, without painting an all-screen reticle or changing document-detection inputs.
- The identity-aware `QuadSmoother` had a mismatch between a six-frame stale-box hide threshold and its eight-frame confirmation for a coherent frame-edge challenger: the box could blink off for two frames, then suddenly return as the challenger. A consistent contender now stays in the confirmation state without that intermediate blank. Alternating/unstable contenders still hide after the configured miss threshold.
- A missing/invalid detection now resets the incompatible-candidate streak. Isolated false contours separated by missed detections cannot cumulatively cause the old outline to disappear. Synthetic tests cover both the default border-delay behavior and interrupted mismatch sequences. Real camera accuracy and device framerate have **not** been measured; this is not a claim of CamScanner algorithm equivalence.

### 0.5.23 — Image to PDF conversion and export

- Before this change Tools → Image to PDF only imported photos and opened the regular page editor; no PDF conversion/export destination was offered. The new flow selects photos or an existing unlocked image-backed document, lets the user include/exclude individual pages and reorder them with a drag handle or up/down arrows, then generates a separate PDF for preview and export.
- **Preview PDF** uses the existing offline PDF renderer. **Save PDF** opens Android's standard `ACTION_CREATE_DOCUMENT` Save As dialog and writes a real `.pdf` to the user-chosen folder, returning without a success toast if cancelled. **Share PDF** sends an `application/pdf` attachment through the Android share sheet.
- A native bridge only accepts generated PDFs staged within app cache before writing to the user-selected SAF URI; no broad storage permission or cloud service is needed. User-edited PDF filename is sanitized and `.pdf` is not appended twice.
- Image content is placed on individual A4 PDF pages, regardless of the original document kind. Deselect/reorder and preview leave the source scans untouched. Screen tests cover selection/reorder/export order, filename normalization, cancelled Save As and original-page preservation. Android 16 destination providers, large-image memory and PDF rendering remain to be verified physically.

### 0.5.22 — Tools Import File

- Previously tapping Tools → Import File showed a `planned` message. It now opens an import-only source sheet with PDF File and Images. Existing document records are hidden to avoid confusing a fresh import with opening an already saved scan.
- PDF import reuses the Android system Storage Access Framework picker and local PDF-to-image rasterization added in `0.5.19`; selecting gallery images copies them into private DocScanner storage. On success the new document preview opens, with no extra duplicate import.
- User-cancelled picker actions keep the import screen open. No cloud or broad device-storage permission was added. Widget tests check that PDF picker invocation works and existing library documents remain hidden.
- Limits: PDFs are flattened to image pages (up to 80 pages / 80 MB). DOCX/PPTX and other non-PDF files are not parsed. Test PDF picker, error recovery and oversized PDFs on Android 16 before confirming device-level completion.

### 0.5.21 — Video Rotate Pages (381565.mp4)

- Tools → Rotate PDF previously opened the document viewer without a page rotation workspace. It now offers existing unlocked documents, Gallery images or a local PDF picker, followed by a visual page grid with Select All, multi-page rotation controls and per-page zoom.
- Left 90°, Right 90°, 180° and Reset change **only local preview state**, including visible orientation badges. Cancel/Back does not write image files or the document index. Four successive quarter-turns cancel out, avoiding unnecessary JPEG re-encoding.
- Done processes changed pages off the UI isolate, preserving original scans, page IDs and order. Files are staged before the updated page records are persisted as one document update; PNG pages retain transparency. Tools and PDF Tools open the updated document preview after Done.
- Tests cover multi-select, rotation direction, Reset/Cancel/net-zero changes, PNG transparency and image corner orientation. Verify actual imported PDFs and Android file viewers on HONOR Android 16 before claiming end-to-end parity.

### 0.5.20 — Video Extract PDF Pages (381564.mp4)

- Previously Tools → Extract PDF Pages opened the general PDF Tools page, where the user had to press a second Extract button and choose page numbers in a small text-only checkbox dialog. The video shows a document picker, visual page checkboxes and Extract as New Document.
- Tools now launches `VideoToolSourcePicker` with app documents, gallery import and the `0.5.19` Android PDF file picker, then `ExtractPdfPagesScreen` with scrollable page thumbnails, zoom, selection count and Select All / Deselect All.
- The new page-confirmation action copies selected pages into an independent editable document, preserving source order and original document pages. It opens the newly created document preview after explicit confirmation. PDF Tools' existing Extract Pages button also launches this same screen.
- Widget tests cover disabled extraction when nothing is selected, choosing noncontiguous pages in ascending order, preserving source pages and select/deselect-all staging. CI and a physical Android 16 acceptance comparison against `381564.mp4` remain pending.

### 0.5.19 — Video PDF to Images (381560.mp4)

- Before this patch, Tools → PDF to Images simply called the Android share sheet for the separate images already stored in DocScanner. It had no PDF import, preview or page selection stage.
- A new Android `ACTION_OPEN_DOCUMENT` PDF picker copies a selected PDF to a private cache file without requiring broad storage permission. The offline Printing/PDFium renderer then rasterizes up to 80 pages at 150 DPI, and imports them as a new image-backed DocScanner document. Individual PNG staging files are removed after the document store copies them; the original SAF document is untouched.
- The `PdfToImagesScreen` shows a two-column page grid, per-page zoom and checkboxes, select/deselect all, JPG/PNG choice, and explicit Save as New (new DocScanner document), Share Images (selected page files) and Save to Gallery (MediaStore). Source document pages remain unchanged.
- `PdfImageExport` transcodes selected images using a background isolate and original dimensions, rather than resizing to thumbnail resolution. Format/dimension unit tests and UI selection widget tests added.
- **Limitations:** importing a password-protected/damaged/oversize PDF can fail; raster import has an 80-MB source and 80-page conversion limit. Imported PDFs are rasterized into editable images, not parsed as original vector text. Android picker/PDFium behavior and export receivers still need HONOR Android 16 verification.

### 0.5.18 — Video PDF to Long Image editing flow

- The Tools action previously sent an existing image-backed document straight to the Android share sheet. Video `381562.mp4` instead shows a source-selection and **long-image preview** stage with a watermark switch and separate save/export choices.
- The new `LongImageStudioScreen` accepts an unlocked existing document or images through the gallery-backed `VideoToolSourcePicker`. Preview and output are stitched on a background isolate; enabling the watermark appends a 56-pixel white footer with a small DocScanner label without covering the original content.
- **Save as New** creates a separate image-backed document and opens its document detail; **Share Image** sends the stitched JPEG; **Share as Images** sends the original separate image pages; **Save to Gallery** uses Android MediaStore. No output is saved until explicitly requested.
- **Share as PDF** slices the stitched result into consecutive readable A4 pages to avoid squeezing a very tall strip into one illegible A4 thumbnail. Original saved pages are not mutated. Existing direct long-image sharing from the Files/document menus still works unchanged.
- *Scope limitation:* these flows operate on DocScanner's image-backed documents or newly imported images. Lossless rasterization of an arbitrary external PDF is still not implemented (K-008). Real-device output quality, long-receipt memory, Android Gallery and share receivers remain to be verified.

### 0.5.17 — Video Extract Text direct flow

- The Tools `Extract Text` action previously opened a selected document and instructed users to find Edit Text elsewhere. That was inconsistent with the `381563.mp4` reference and awkward after removing the Tools `Edit Text` tile.
- Tools and Home Quick OCR now open the video-inspired source picker, then `ExtractTextScreen` immediately processes the chosen document. Editing stays in a dedicated plain-text workspace, separate from overlay-on-image editing.
- Re-recognize in English or Bengali using the offline ML Kit/Tesseract pipeline; switch language performs a fresh OCR pass even if a previous cached transcript exists. Failed re-recognition preserves the user's edited text. Clipboard, Select All, DOCX built from the **edited** content, and TXT share actions remain explicit.
- Native OCR recognition and Android receiving-app behavior must still be checked on HONOR Android 16; this change does not claim all five source-video flows are finished.

### 0.5.16 — New image-editing Tools and five reference clips

- `381560.mp4` illustrates PDF → individual images, `381562.mp4` PDF → long image (bottom watermark/share), `381563.mp4` Extract Text OCR, `381564.mp4` selective PDF page extraction and `381565.mp4` rotating individual pages. These are **reference observations**, not evidence that every existing workflow has pixel-identical UI.
- The three requested image tools previously had two placeholder actions and a fixed-size-only resizer. All three now open a new image editor with Gallery, Camera and unlocked DocScanner-document sources, a preview, Save as New and Share. No edit triggers a save notification before Save.
- Passport mode supports 35×45 mm, 2×2 inch, 30×40 mm, 40×60 mm and 50×50 mm at 300 DPI, pan/zoom adjustments, simple backgrounds and 4×6 inch sheets with capacity-aware copy counts.
- BG Remover flood-fills an edge-connected, approximately uniform colour locally; it outputs transparent PNG or recolours the removed area. This is not a semantic AI portrait matting engine.
- Image Resizer adds percentage presets, custom width/height, aspect lock, JPEG quality and PNG/JPEG output. Photos are processed outside the UI isolate. Tools-grid Edit Text and Split PDF are removed, while document-level text editing and other PDF tools remain.
- Pure image-processing and widget-opening tests added. Live device checks are needed for picker behavior, memory/latency, camera permissions, delicate hair edges, image fidelity and share targets.

### 0.5.11 candidate — video regression (381334.mp4)

- ID capture explicitly prefers a centred, landscape card to a larger background bank form; normal A4 page detection keeps its separate outer-sheet preference.
- When no credible card quad exists, review must allow adjusting the original image instead of saving a guessed form crop.
- Full-size originals survive the Front/Back capture flow; reopening Crop uses the source, not an already clipped crop.
- Card-size A4 placement is closer to physical ID-1 proportions, and the on-screen preview matches the saved composer.
- New native candidate-selection and Dart page-scale regression tests are included. CI passed in the `0.5.11` run; **a real-device retest is not yet recorded.**

### 0.5.12 candidate — Single Scan video regression (381360.mp4, 381362.jpg)

- A portrait letter can contain stronger horizontal text/table edges than its page outline. Suspicious landscape inner bands are no longer perspective-warped into an irreversible partial page.
- If the current live frame has a credible page-like quadrilateral and the still framing matches, that recent outline seeds the editable **Adjust corners** screen, not an automatic warp. Otherwise the full upright capture opens for manual crop.
- The existing ID Card crop strategy remains separate and unchanged.
- **Adjust corners** actions now sit inside the Android bottom safe area; the full photograph remains available for correction.
- Native geometric unit tests cover credible page, suspicious horizontal strip, sudden shrink, orientation mismatch and malformed quadrilaterals. **CI passed in run #42458973854; device confirmation not yet recorded.**

### 0.5.13 candidate — improved Auto Crop after scan

- Still scans now compare neutral/coloured paper against the background in the frame corners as a separate, offline page-boundary signal. The method works when paper and desk have similar saturation but visibly different brightness, even with bold internal text lines.
- Shutter stills search more contour candidates and run line/texture fallbacks when the only strong rectangle seems to be content rather than a whole page; live preview retains the existing lighter path.
- Outer-sheet selection tolerates a more subdued page boundary only if its polygon encloses the inner rectangle, has credible paper geometry and independently supported edges/contrast.
- A new colour-mask candidate replaces an existing CV crop only if the page is credible and substantially larger; otherwise the original still/crop behavior remains. Card-specific ranking, manual shutter, original-image preservation and reversible four-corner editing remain intact.
- Native regression tests cover dense printed letters, light-grey paper on a grey desk, uniformly blank scenes, cut-off background panels, subdued outer page borders and square false positives. **CI and physical device confirmation not yet recorded.**

### Post-0.5.13 — blue poster versus yellow inner label (381526.mp4)

- The video shows a credible live outline around the complete blue signboard, followed by a still-image crop of only the central yellow title. The final saved thumbnail loses the logo and lower text.
- A conservative saturated-panel detector now looks for a connected outer-colour region on heterogeneous backgrounds (stone above, patterned table below). It competes with the still contour only when that contour is small, and must pass the existing credible-outer-page and substantial-growth criteria before being selected. This is not specific to blue pixels.
- The still-crop guard now rejects a small centred inner band even if CameraX/EXIF reports a landscape or transposed JPEG. Normal page captures keep the existing native detector; uncertain captures preserve the full upright image and open the existing editable four-corner review rather than warping a guessed inner label.
- Added native geometry regressions for a full poster, yellow inner title in both orientations, full landscape page, edge-touching document and absent still quad; synthetic pixel regressions check poster recovery against a patterned background and reject uniform/undersized coloured patches. **The source video is not a raw camera still; a same-scene device retest is required to establish the exact detector failure and the quality of the final automatic crop.**

### 0.5.14 — CamScanner-like stable four-corner tracking (381530.mp4)

- The reference tracks the outside of a blue patterned textile, while DocScanner's live polygon strays over the tall brown/black chair. The static full-preview turquoise border also creates an extra misleading frame.
- Normal Scan live RGBA analysis now checks a second downscaled saturated-colour panel candidate when the OpenCV result is absent, elongated or overly large. A conservative geometric selector changes targets only for a strongly elongated background around the same centre or a small nested title. ID Card boundary ranking remains separate.
- Dart tracking keeps the same-document identity gate, confirms challengers across four mutually consistent frames, rejects crossed/invalid quads and adaptively blends pixel-level jitter versus deliberate movement. Pause, resume and lens switching clear stale tracking state. The permanent preview border is removed; only the detected document is outlined.
- Synthetic native live-cloth and competing-chair tests plus Dart movement/jitter/false-candidate tests were added. **No physical-phone result is claimed before a same-scene retest on HONOR VKP-NX9.**

### 0.5.15 — Prevent green box jumps and clarify tint (381536.mp4)

- The 16-second clip repeatedly jumps between the blue textile and full-frame/near-frame chair contours. A code bug in `DoclensController` used `smoother?.add(raw) ?? raw`, so when the smoother intentionally suppressed a bad quad, the unsafe raw quad was displayed anyway. The controller now respects null rejections.
- Native detection independently inspects a small saturated-colour region for every normal Scan frame; it can prefer a fully visible cloth over a camera-border chair, and hides near-frame contours when no credible cloth/page evidence exists. ID Card detection remains separate.
- The Dart tracker ignores sub-0.6%-of-frame movement and demands additional confirmations before a sudden, larger border-hugging rectangle replaces a tracked document. The actual document polygon, not the entire camera preview, receives a faint mint-green fill. This overlay is **visual feedback only**, not an algorithmic detection input.
- Regression tests cover native frame-border rejection, transient/reappearing quads, deadband jitter, slow takeover and the controller's rejected-quad leak. **Manual capture remains unchanged; measure actual 12 Hz CPU/frame time and compare the same moving scene on HONOR VKP-NX9 after CI succeeds.**

## Recent CI note

During `0.5.10` publishing, an oversized `doclens_screen.dart` upload was initially incomplete; the first CI run failed to find the source. The file was re-uploaded with SHA verification in follow-up commit `1c69de9`, the analyzer import was cleaned, and the subsequent run succeeded. This is a **resolved publishing incident**, not an outstanding scanner bug.
