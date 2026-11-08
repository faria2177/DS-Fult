# DocScanner — Prioritized TODO

**Updated:** 2026-11-08. This is a forward-looking engineering queue, not a claim that each item is a confirmed bug. Verified defects belong in [BUGS.md](BUGS.md); uncertainties belong in [KNOWN_ISSUES.md](KNOWN_ISSUES.md).

## P0 — Complete real-device acceptance

- [ ] **T-001: Verify live four-corner detection on HONOR VKP-NX9, Android 16.** Use A4, Legal, ID Card, textured/dark backgrounds, a page with an inner table, glare and partial occlusion. The visible contour and final saved crop must cover the **same complete page** where edges are reliable. Collect before/after images and logs for failures.
- [ ] **T-002: Verify camera mode transitions.** Repeat Single ↔ Batch ↔ ID Cards ↔ Scan 20 times; no unintended black flash, mirrored/reflected texture, duplicate camera owner or stale overlay. Distinguish camera-configuration changes, which may legitimately rebind, from UI-only switches.
- [ ] **T-003: Verify full ID Card workflow.** Select ID Card and Driver License → capture/import Front and Back → individually adjust four corners and orientation → see both on one A4 sheet → Save → reopen → export PDF. Expected: one thumbnail and exactly one PDF page per card pair. Test partial capture, cancel, Back and gallery replacement.
- [ ] **T-004: Verify General card mode.** Capture at least three images in one session, review 01/02/03 independently, remove/reorder if available, save three separate document pages and export a three-page PDF. No two-image cap in General.
- [ ] **T-005: Verify UI safe areas.** Check bottom toolbar/buttons, Android navigation bar, rotation, tall and narrow devices, light/dark mode, long-press selection and back navigation. No clipped or hidden actions.
- [ ] **T-006: Capture real-device test matrix.** Add screenshots and device/build/version details to bug reports; record reproducible regressions in `BUGS.md` with precise steps and expected/actual behavior.

## P1 — Data and processing quality

- [ ] **T-101: Re-edit saved card sides.** Persist front/back source image metadata and files alongside the composed A4 sheet; offer separate side editing after the document is saved. Do not lose existing composite documents during migration.
- [ ] **T-102: Atomic document-index persistence.** Write `index.json.tmp`, fsync if available and safely replace/rename the index; recover from interrupted writes. Test corrupt/partial JSON and idempotent startup.
- [ ] **T-103: Recoverable cleanup.** Make deletion behavior explicit (trash/undo/retention) and safely garbage-collect unreachable scan/edit files. Never delete original capture files without an agreed recovery policy.
- [ ] **T-104: Improve contour scoring and crop review.** Add measured failure examples and native regression fixtures for complete A4 sheets, nested rectangles, narrow cards and low contrast. Do not enlarge crops to the camera frame without evidence.
- [ ] **T-105: Audit image quality.** Tune resolution, noise reduction, shadows, text sharpness and JPEG export quality against reference captures. Preserve originals; make enhancements reversible.
- [ ] **T-106: OCR/export quality tests.** Add multi-language scanned fixtures, word-layout checks and Excel table fixtures. Validate Word share receivers and correct Office MIME types on Android.
- [ ] **T-107: Clarify PDF security.** If the user explicitly requests real encryption, implement PDF encryption separately from app access PINs, with clear recovery/export behavior. Never relabel the current PIN as encryption.
- [ ] **T-108: Align edit/preview actions.** Confirm Compare, Filter, Crop, Rotate, Retake and Watermark preserve the intended page and only show save notifications on an explicit user save.

## P2 — Product polish and engineering hygiene

- [ ] **T-201: Video-reference acceptance sheets.** For each reference recording, save a timestamp-to-screen map, control labels, interactions and screenshots. Prioritize functionality over decorative 1:1 pixel matching.
- [ ] **T-202: Performance profiling.** Measure camera first-frame time, contour FPS, mode-switch latency, 20-page batch memory, PDF generation and cold start. Avoid adding unmeasured dependencies.
- [ ] **T-203: APK size audit.** Review per-ABI native libraries, assets, duplicates and licenses; keep required detector/OCR files. Record APK size before/after each change.
- [ ] **T-204: Automated visual regression.** Add stable widget/golden tests for the ID Card A4 view, Files multi-selection, document grid and settings; use deterministic assets rather than camera hardware in CI.
- [ ] **T-205: Improve contributor guidance.** Keep this TODO, the decision log and issue register synchronized with each meaningful implementation milestone.
- [ ] **T-206: Accessibility/localization.** Check screen reader semantics, minimum tap targets, high-contrast text, Bengali copy and user-facing error strings.

## Definition of done for each TODO

1. Evidence-based reproduction or measurable acceptance criteria recorded.
2. Change limited to the required module(s), preserving local-only behavior and existing working processing.
3. Tests added/updated; `flutter analyze`, `flutter test` and native tests pass when relevant.
4. New release APK builds successfully in GitHub Actions.
5. Physical-device check completed for camera/crop/navigation work, or explicitly marked pending.
6. Update [PROGRESS.md](PROGRESS.md), [BUGS.md](BUGS.md), [KNOWN_ISSUES.md](KNOWN_ISSUES.md) and [DECISIONS.md](DECISIONS.md) where applicable.
