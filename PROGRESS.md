# DocScanner — Progress Snapshot

**Last documented:** 2026-11-08  
**Current candidate release:** `0.5.12+26`
**Last fully successful CI baseline before this patch:** [GitHub Actions run #42454738856](https://github.com/faria2177/DS-Fult/actions/runs/42454738856)
**Baseline commit:** [`d65478e`](https://github.com/faria2177/DS-Fult/commit/d65478e8d17cef07c6f4e179396fbcb6aa9010a1)

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
| `0.5.11` | Card-specific OpenCV quad ranking, source-image re-crop recovery, improved true-size A4 card layout | Implemented / CI + physical device verification pending |
| `0.5.12` | Single Scan crop guard against internal horizontal text bands; recent credible live outline seeds manual review, full original preserved; Adjust corners actions respect navigation safe-area | Native regression tests added; CI and device verification pending |

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
| Password protection | App UI access PIN | Does not encrypt PDFs/files |
| Cloud, Ask AI | Intentionally absent | Do not add without explicit new scope |

## Next milestone definition

The next release should close **at least one P0 task** in [TODO.md](TODO.md) with reproducible before/after evidence from the real device. Each code change needs `flutter analyze`, `flutter test`, relevant native tests and an APK build. Update this file, the issues register and the release version only after validation.

### 0.5.11 candidate — video regression (381334.mp4)

- ID capture explicitly prefers a centred, landscape card to a larger background bank form; normal A4 page detection keeps its separate outer-sheet preference.
- When no credible card quad exists, review must allow adjusting the original image instead of saving a guessed form crop.
- Full-size originals survive the Front/Back capture flow; reopening Crop uses the source, not an already clipped crop.
- Card-size A4 placement is closer to physical ID-1 proportions, and the on-screen preview matches the saved composer.
- New native candidate-selection and Dart page-scale regression tests are included. **Passing tests and a real-device retest are not yet recorded.**

### 0.5.12 candidate — Single Scan video regression (381360.mp4, 381362.jpg)

- A portrait letter can contain stronger horizontal text/table edges than its page outline. Suspicious landscape inner bands are no longer perspective-warped into an irreversible partial page.
- If the current live frame has a credible page-like quadrilateral and the still framing matches, that recent outline seeds the editable **Adjust corners** screen, not an automatic warp. Otherwise the full upright capture opens for manual crop.
- The existing ID Card crop strategy remains separate and unchanged.
- **Adjust corners** actions now sit inside the Android bottom safe area; the full photograph remains available for correction.
- Native geometric unit tests cover credible page, suspicious horizontal strip, sudden shrink, orientation mismatch and malformed quadrilaterals. **CI/device confirmation not yet recorded.**

## Recent CI note

During `0.5.10` publishing, an oversized `doclens_screen.dart` upload was initially incomplete; the first CI run failed to find the source. The file was re-uploaded with SHA verification in follow-up commit `1c69de9`, the analyzer import was cleaned, and the subsequent run succeeded. This is a **resolved publishing incident**, not an outstanding scanner bug.
