# DocScanner — Bug and Regression Register

**Last reviewed:** 2026-11-10
**Baseline:** `0.5.35+49` (candidate; physical-device verification pending)
**Scope:** Reproducible failures, historical regressions and their fix status. Potential limitations belong in [KNOWN_ISSUES.md](KNOWN_ISSUES.md), not automatically in the Open list.

## Status rules

- **OPEN — confirmed:** Reproduced on a named build/device with evidence.
- **FIX IN CODE — device pending:** Implementation and/or unit tests exist, but original physical-device failure needs retesting.
- **RESOLVED — CI verified:** Reproduction at the code/build level is fixed and the affected CI check passes; device verification may still be required if the bug was hardware-specific.
- **CLOSED — device verified:** The affected physical workflow is confirmed fixed; include build, device and evidence.

## Currently confirmed open bugs

| ID | Evidence | Observed behavior | Current status | Required confirmation |
| --- | --- | --- | --- | --- |
| B-001 | Video `381772.mp4`, ~00:03–00:10, HONOR Android 16 screen recording | A4 page is fully enclosed by green live corners, but shutter review and saved scan show only a landscape fragment of the inner timetable | OPEN — confirmed again in 0.5.31. The 0.5.32 candidate adds reciprocal-aspect missing-EXIF correction from live CameraX rotation, stricter still/full-page comparison and raw-source manual review for uncertain inner-table crops; CI/device verification pending | Rescan the same portrait A4 timetable on HONOR; compare green outline, captured raw still, detected quad, manual review and final page. Confirm all four paper edges, header and last row survive; repeat with landscape A4 and actual ID cards to catch false rotation or over-rejection |
| B-001i | Video `381776.mp4`, ~00:06–00:12, HONOR Android 16 | Full A4 is outlined correctly in the camera, yet its bitmap is sideways in Adjust corners and the cropped result includes a desk strip | OPEN for hardware retest. `0.5.33` registers a small recent live frame with the captured JPEG using pixel correlation, validates any quarter-turn and refuses to reuse unverified live corners. | Test on HONOR VKP-NX9; compare raw JPEG orientation, editor handles, page margins and output before and after a shutter press. If still mismatched, collect original unmodified JPEG + EXIF orientation and CameraX logs. |
| B-001j | Video `381781.mp4`, ~00:02–00:06, HONOR Android 16 | Green live quad frames the entire A4, but Adjust corners receives a wide JPEG that has lost part of the page; four white handles default to the whole frame and final preview still includes desk | FIX IN CODE — device pending. `0.5.34` uses shared CameraX `UseCaseGroup`/`ViewPort`, explicit screen rotation and display-oriented HD resolution; removes unconditional full-image fallback when a separate credible still-page outline was detected. Root cause at Camera2/EXIF level remains unverified. | Build 0.5.34 APK and rescan exactly the same A4 on HONOR. Confirm title and signatures, four editable corners, portrait output with no desk. Include raw JPEG/EXIF and CameraX logs if the image still differs from the live preview. |
| B-001k | Video `381803.mp4`, ~00:14–00:24, HONOR Android 16, compared with CamScanner ~00:00–00:07 | DocScanner's live green corners latch onto the printed table inside a bank application, leaving its letterhead and white margins outside the proposed crop; after review the final page includes the desk and another sheet | FIX IN CODE — device pending. `0.5.35` conditionally searches farther when the live candidate resembles an inner form and prefers a larger, independently observed enclosing page only if four corners and edge evidence are credible. This is not proof the outer contour is detectable in the supplied camera scene. | Build 0.5.35 APK; reframe until all four paper corners are visible and compare the live quad, Adjust corners and final exported page with CamScanner. If still inaccurate, collect only redacted/synthetic photos and frame-time diagnostics, never post the personal bank form to public GitHub. |
| B-010 | Video `381526.mp4`, ~00:18–00:28, HONOR Android 16 screen recording | Single Scan live outline follows the entire blue Grameenphone poster; shutter review, editor and saved thumbnail contain only the smaller yellow inner label | OPEN — confirmed in video. Post-`0.5.13` still-only saturated outer-panel candidate and orientation-independent compact-crop guard added; CI/device results pending | Install an APK containing this patch; scan the same poster. Expect full-board auto-crop if boundaries are reliable, otherwise full-original corner review. Log still/live quads and compare all four edges to CamScanner's accepted scan |
| B-011 | Videos `381530.mp4` and `381536.mp4` (00:02, 00:07, 00:13–00:15), HONOR Android 16 | The green quad intermittently leaves the blue textile for the chair or a preview-edge-spanning rectangle, then jumps back; earlier scan also cropped only the inner motif | OPEN — reproduced on video. `0.5.15` suppresses rejected raw quads and adds near-edge confirmation/deadband. `0.5.24` actually enables a very pale green fill in the camera overlay and fixes two temporal gap/blink cases in Dart, with new synthetic tests; real-device outcome is unverified | Recreate 381536 scene while moving and stopping repeatedly; green quad must remain near the cloth, not jump to camera edges; rejection should display no false outline. Measure FPS/frame cost; verify full cloth remains in captured review and compare with CamScanner |
| B-013 | `381742.mp4` ~00:09 and ~00:13–00:21 versus CamScanner `381739.mp4` ~00:33 | To Word on Android 16 can throw an obfuscated ML Kit Java `getClass()`-on-null PlatformException; recovered dense timetable text is mostly unreadable and Bengali/Unicode `Save as PDF` reports Latin-only support | FIX IN CODE — 0.5.31 bundles English Tesseract fallback, makes image-capable AI OCR optional with separate upload consent, preserves tabular Word structure, and adds shaped-raster Unicode PDF. Native exception's actual cause is unconfirmed; CI and device retest pending | Install 0.5.31 on HONOR; retry same non-sensitive timetable offline and with each approved vision model; compare all visible text/cells and export both DOCX/XLSX; check Save as PDF with Bengali and remove any raw Java stack trace from UI |

## Historical fixes requiring targeted hardware retest

| ID | Original symptom | Fix introduced | Status | Required confirmation |
| --- | --- | --- | --- | --- |
| B-002 | Single/Batch/ID Cards switches show black reflection/preview flicker | `0.5.1`: UI-only mode changes avoid camera rebind; controlled rebind remains when required | FIX IN CODE — device pending | Repeat mode switching on HONOR VKP-NX9; record preview and CameraX logs |
| B-003 | ID Front and Back are saved as separate document thumbnails/pages instead of one A4 sheet | `0.5.10`: `IdCardPageComposer` + `compositeCardPages` + PDF branch | FIX IN CODE — device pending | Scan both sides, reopen grid, export and inspect PDF page count |
| B-004 | Repeated scan fails to crop bright paper from saturated blue fabric | `0.5.6`: conditional colour/contrast fallback and native tests | FIX IN CODE — device pending | Repeat capture with the same light-paper/dark-fabric scene |
| B-005 | `Me → Scan` and camera More Settings can drift apart | `0.5.2`: shared seven-option page and one persisted preference source | RESOLVED — CI verified; device retest useful | Toggle each option, reopen both entry points and restart app |
| B-006 | Long-press Files selection action/checkmark visibility and bottom-bar overlap | `0.5.5`: selection controls, safe-area-aware Files navigation | FIX IN CODE — device pending | Select 1 and many files on Android 16 with gesture/3-button navigation |
| B-008 | Video `381334.mp4`: ID card over a bank form is cropped with background strips and clipped text; final A4 cards are oversized | `0.5.11`: card-aware native quad ranking, safe original-image re-crop and smaller A4 print slots | FIX IN CODE — CI verified; device pending | On HONOR VKP-NX9, scan both sides over a busy form, inspect corners, adjust/reopen Crop, verify no lost text and one-page PDF |
| B-009 | Video `381360.mp4` and image `381362.jpg`: Single Scan live preview outlines the portrait letter, but captured still selects only the middle horizontal text band; Reset/Continue buttons are too close to Android navigation bar | `0.5.12`: preserve full still on suspicious inner strip; use recent live outline only as an editable hint and put corner controls inside SafeArea. `0.5.13`: add a separate still-image background/paper mask and more complete outer-page candidate search to recover automatic cropping where safe | FIX IN CODE — 0.5.12 CI verified, 0.5.13 CI/device pending | Scan same letter on HONOR VKP-NX9: header, closing and signature must remain visible; verify automatically cropped page or safe full-original review, plus reachable buttons and complete final output |
| B-012 | Tools → Image to PDF only opened the ordinary image importer/editor without PDF Preview/Save/Share | `0.5.23`: explicit selected-page PDF builder, preview, SAF Save As and Share | FIX IN CODE — CI/device pending | Convert 2–3 pictures, reorder, Save as PDF to Downloads and reopen in a PDF viewer; confirm page count and preserved originals |

## Resolved build/publishing incident

| ID | Incident | Resolution | Status |
| --- | --- | --- | --- |
| B-007 | Initial `0.5.10` GitHub upload of large `third_party/doclens/lib/src/widgets/doclens_screen.dart` was incomplete; analyzer could not import it | Full blob re-uploaded and its SHA verified; one unused import removed; subsequent run #42440988584 passed native tests, analysis, widget tests and APK build | RESOLVED — CI verified |

## Bug-report template

Copy the following into a GitHub issue or add a row to this register:

```markdown
### B-XXX — Short description
- Status: OPEN — confirmed / under investigation / fix in code / closed
- Severity: crash / data loss / core scan / visual / minor
- App version and commit:
- Device model, Android version and navigation mode:
- Input file or reference video + timestamp:
- Steps to reproduce: 1. ... 2. ... 3. ...
- Expected:
- Actual:
- Frequency: every time / intermittent / unknown
- Evidence: screenshot, screen recording, redacted logcat excerpt
- Suspected code area (if known):
- Proposed fix and regression test:
- Verification result + run/device/date:
```

Never attach government ID data, personal document contents, credentials, API keys or identifiable user records to public issues. Redact or replace them with synthetic fixtures.

## Closure policy

For camera, crop, OCR and Android UI bugs, a green GitHub Actions run is **necessary but insufficient** for CLOSED. Record the real-device result, image/video evidence and exact build. Move the remaining quality risks to [KNOWN_ISSUES.md](KNOWN_ISSUES.md) when appropriate. Update [PROGRESS.md](PROGRESS.md) at the same time.
