# DocScanner — Bug and Regression Register

**Last reviewed:** 2026-11-08  
**Baseline:** `0.5.23+37` (candidate; physical-device verification pending)
**Scope:** Reproducible failures, historical regressions and their fix status. Potential limitations belong in [KNOWN_ISSUES.md](KNOWN_ISSUES.md), not automatically in the Open list.

## Status rules

- **OPEN — confirmed:** Reproduced on a named build/device with evidence.
- **FIX IN CODE — device pending:** Implementation and/or unit tests exist, but original physical-device failure needs retesting.
- **RESOLVED — CI verified:** Reproduction at the code/build level is fixed and the affected CI check passes; device verification may still be required if the bug was hardware-specific.
- **CLOSED — device verified:** The affected physical workflow is confirmed fixed; include build, device and evidence.

## Currently confirmed open bugs

| ID | Evidence | Observed behavior | Current status | Required confirmation |
| --- | --- | --- | --- | --- |
| B-010 | Video `381526.mp4`, ~00:18–00:28, HONOR Android 16 screen recording | Single Scan live outline follows the entire blue Grameenphone poster; shutter review, editor and saved thumbnail contain only the smaller yellow inner label | OPEN — confirmed in video. Post-`0.5.13` still-only saturated outer-panel candidate and orientation-independent compact-crop guard added; CI/device results pending | Install an APK containing this patch; scan the same poster. Expect full-board auto-crop if boundaries are reliable, otherwise full-original corner review. Log still/live quads and compare all four edges to CamScanner's accepted scan |
| B-011 | Videos `381530.mp4` and `381536.mp4` (00:02, 00:07, 00:13–00:15), HONOR Android 16 | The green quad intermittently leaves the blue textile for the chair or a preview-edge-spanning rectangle, then jumps back; earlier scan also cropped only the inner motif | OPEN — reproduced on video. `0.5.14` native/Dart CI passed. `0.5.15`: fixed raw-quad reappearance after smoothing returned null; new frame-edge rejection, persistent panel comparison, conservative challenger confirmation, deadband and pale-green valid-quad tint; fresh CI/device check pending | Recreate 381536 scene while moving and stopping repeatedly; green quad must remain near the cloth, not jump to camera edges; rejection should display no false outline. Measure FPS/frame cost; verify full cloth remains in captured review and compare with CamScanner |

## Historical fixes requiring targeted hardware retest

| ID | Original symptom | Fix introduced | Status | Required confirmation |
| --- | --- | --- | --- | --- |
| B-001 | Live A4 contour surrounds the sheet, but captured still clips to an inner table | `0.5.9`: native high-resolution still candidate comparison, full-page preference with edge evidence | FIX IN CODE — device pending | Capture the original A4/table scene and check all four sheet edges in saved output |
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
