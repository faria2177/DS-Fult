# DocScanner — Architecture Decision Records (ADRs)

**Last reviewed:** 2026-11-08. These decisions summarize current implementation and user-confirmed constraints. A new decision should include date, context, choice, consequences, alternatives and affected code; do not silently reverse an accepted decision.

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
**Decision:** Remove **Mega Scan, Long Document, Driver License, Bank Card, Photo Translation, Scan Code, To PPT, Erase Marks, Restore Photo** from the Tools grid as requested. Code or entry points elsewhere may remain if useful; not every internal implementation is a visible Tools item.  
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

## How to change a decision

For a meaningful reversal, append a new `ADR-011+` entry with the proposed alternative, user approval when scope changes, migration/backward-compatibility behavior, tests and rollback. Mark the old ADR `Superseded by ADR-XXX`; preserve the historical rationale.
