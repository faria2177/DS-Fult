# DocScanner — Bug and Regression Register

**Last reviewed:** 2026-11-08  
**Baseline:** `0.5.10+24`  
**Scope:** Reproducible failures, historical regressions and their fix status. Potential limitations belong in [KNOWN_ISSUES.md](KNOWN_ISSUES.md), not automatically in the Open list.

## Status rules

- **OPEN — confirmed:** Reproduced on a named build/device with evidence.
- **FIX IN CODE — device pending:** Implementation and/or unit tests exist, but original physical-device failure needs retesting.
- **RESOLVED — CI verified:** Reproduction at the code/build level is fixed and the affected CI check passes; device verification may still be required if the bug was hardware-specific.
- **CLOSED — device verified:** The affected physical workflow is confirmed fixed; include build, device and evidence.

## Currently confirmed open bugs

No **newly verified, device-reproduced** bug was provided after the `0.5.10` successful CI run. This means **not yet confirmed**, not “bug-free.” File any new regression using the template below before promoting it to an OPEN issue.

## Historical fixes requiring targeted hardware retest

| ID | Original symptom | Fix introduced | Status | Required confirmation |
| --- | --- | --- | --- | --- |
| B-001 | Live A4 contour surrounds the sheet, but captured still clips to an inner table | `0.5.9`: native high-resolution still candidate comparison, full-page preference with edge evidence | FIX IN CODE — device pending | Capture the original A4/table scene and check all four sheet edges in saved output |
| B-002 | Single/Batch/ID Cards switches show black reflection/preview flicker | `0.5.1`: UI-only mode changes avoid camera rebind; controlled rebind remains when required | FIX IN CODE — device pending | Repeat mode switching on HONOR VKP-NX9; record preview and CameraX logs |
| B-003 | ID Front and Back are saved as separate document thumbnails/pages instead of one A4 sheet | `0.5.10`: `IdCardPageComposer` + `compositeCardPages` + PDF branch | FIX IN CODE — device pending | Scan both sides, reopen grid, export and inspect PDF page count |
| B-004 | Repeated scan fails to crop bright paper from saturated blue fabric | `0.5.6`: conditional colour/contrast fallback and native tests | FIX IN CODE — device pending | Repeat capture with the same light-paper/dark-fabric scene |
| B-005 | `Me → Scan` and camera More Settings can drift apart | `0.5.2`: shared seven-option page and one persisted preference source | RESOLVED — CI verified; device retest useful | Toggle each option, reopen both entry points and restart app |
| B-006 | Long-press Files selection action/checkmark visibility and bottom-bar overlap | `0.5.5`: selection controls, safe-area-aware Files navigation | FIX IN CODE — device pending | Select 1 and many files on Android 16 with gesture/3-button navigation |

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
