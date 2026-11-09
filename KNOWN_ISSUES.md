# DocScanner — Known Issues and Limitations

**Last reviewed:** 2026-11-09
**Baseline:** `0.5.19+33` candidate; hardware verification pending.
This list separates **confirmed implementation limits** from **risks that need physical-device validation**. Do not interpret “not tested” as “broken.” For reproducible bugs see [BUGS.md](BUGS.md).

## Confirmed implementation limitations

| ID | Topic | Current behavior and impact | Possible next step |
| --- | --- | --- | --- |
| K-001 | App lock vs encryption | The document PIN restricts DocScanner UI access. Images and exported PDFs are **not encrypted** by this mechanism. | Design true file/PDF encryption only if explicitly requested (TODO T-107) |
| K-002 | Saved card-side re-editing | New ID Card/License/Bank Card documents store a **composed A4 JPEG** as a page. Individual Front/Back images are editable during review, but separate side data is not persisted for later independent edits. | Persist source-side assets and migration metadata (T-101) |
| K-003 | Smart Erase and image text replacement | Local pixel interpolation/brush algorithms are not generative semantic inpainting. Textured backgrounds can retain seams or artifacts. | Quality fixtures and explicitly labeled local tools |
| K-004 | DOCX conversion | Word output is editable OCR text, not full original layout/font reconstruction. | Layout analysis and compare real-document exports |
| K-005 | XLSX conversion | Spreadsheet columns are inferred from tabs/repeated spaces in OCR; original table geometry can be lost. | Table-cell detector and test fixtures (T-106) |
| K-006 | PPTX conversion | PowerPoint files contain scanned page **images** on slides; their text/shapes are not independently editable. | Only promise editable objects after actual reconstruction support |
| K-007 | Bengali OCR layout | Bundled Bengali Tesseract supports text recognition, but reliable Bengali word bounding boxes and arbitrary-layout editing are not provided. | Model/layout improvements and physical fixtures |
| K-008 | Native imported PDFs | `0.5.19` adds offline raster import of external PDF files for PDF to Images, but the resulting DocScanner pages are bitmaps. Direct, lossless editing of imported vector text/layout is not available. | Separate PDF parser/content-edit architecture if required |
| K-009 | Document index writes | `index.json` is currently written directly, without an atomic temp-file swap. Interrupted writes may require recovery; unreadable source index is copied with a `.recovery` suffix. | Atomic persistence and corrupt-file tests (T-102) |
| K-010 | Deletion/storage cleanup | The app may retain older backing image files after document/page deletion to avoid premature data loss. This can grow storage usage. | Design recoverable trash and controlled garbage collection (T-103) |
| K-011 | Public share links | Without a cloud host, DocScanner cannot generate a public document URL; local Android sharing is available. | Retain offline explanation unless cloud scope changes |
| K-012 | BG Remover quality | The offline colour/flood-fill remover handles relatively uniform edge-connected backgrounds. It does not reconstruct hair, transparent objects or complex indoor scenes like an AI portrait segmentation model. | Evaluate a licensed on-device segmentation model only if quality requirements justify extra APK size and device cost |
| K-013 | Passport photo acceptance | The presets set nominal pixel sizes at 300 DPI but cannot automatically verify face position, expression, lighting or country-specific biometric requirements. Users must manually frame and confirm photos before official use. | Add country-specific rule templates, face measurements and preview validation if requested |

## Device-dependent or unverified risks

| ID | Area | What still needs checking |
| --- | --- | --- |
| R-001 | Auto Crop accuracy and live tracking | `0.5.13` adds still-only contrast segmentation; `0.5.15` rejects some frame-boundary live false positives and runs a small colour-mask check on every normal live frame. These may improve textile tracking but can hide an extremely close page or increase per-frame CPU. Patterned backgrounds, glare, low-contrast paper edges and partially off-frame sheets can still defeat detection. Originals/manual four-corner review remain the fallback. Validate A4/Letter/Legal, ID Card and receipts on device. |
| R-002 | Mode switching | Some configuration changes intentionally rebind the native camera. Verify no unwanted reflection/black flash on the target HONOR Android 16 device. |
| R-003 | Reference video fidelity | Similar Flutter UI and interaction flow do **not** guarantee pixel-identical colors, typography, motion, overlays or native processing output across screen sizes. |
| R-004 | Navigation/safe areas | Verify toolbar and dialog positioning with Android gesture navigation and three-button navigation. |
| R-005 | Export receivers | Android share targets, Office viewers and printers vary by installed apps and permissions; validate opening each output type. |
| R-006 | OCR model installation | The Bengali model is downloaded and bundled during **build**. A failed dependency download can break CI; runtime scans should not require downloading it again. |
| R-007 | APK size/third-party binaries | Native `.so` libraries and OCR/model assets increase APK size. Audit ABI packaging, binary provenance and license/redistribution rights before public distribution. Do not delete detector dependencies without dependency mapping. |
| R-008 | General mode limits | UI allows many General pages, but very long sessions may use significant RAM and storage; test large batches on low-memory hardware. |
| R-009 | Extract Text device OCR and share | `0.5.17` opens a direct editable text workflow and uses the offline Latin/Bengali recognizers. Verify actual OCR performance, Bengali model presence, keyboard/safe areas, clipboard, DOCX receivers and direct picker/camera transitions on HONOR Android 16. Edited OCR text is exported or copied explicitly; it does not silently rewrite the original document's saved transcript. |
| R-010 | Long image preview/print fidelity | `0.5.18` adds a preview, an opt-in watermark footer, local Save as New, individual-page image share, paginated A4 PDF share and Android Gallery export. Confirm image orientation, output pixel dimensions, long-receipt readability, MediaStore permissions and share receivers on HONOR Android 16. Direct import of arbitrary external PDFs is not supported by this image-backed conversion flow (K-008). |
| R-011 | PDF import and rasterization | `0.5.19` imports device PDFs via Storage Access Framework and rasterizes up to 80 pages at 150 DPI, using a private temporary copy capped at 80 MB. Verify permission handling, cancellation, password-protected PDFs, complex embedded fonts, rotated/landscape pages and OCR-uncertain output on HONOR Android 16. Original PDF vector/text layers are not preserved in JPG/PNG. |

## Intentional exclusions (not bugs)

- No **Ask AI**, account login, cloud backup, cloud sync or paid AI service.
- Removed Tools-grid entries: Mega Scan, Long Document, Driver License, Bank Card, Photo Translation, Scan Code, To PPT, Erase Marks and Restore Photo. Internal helpers or other navigation routes may still exist.
- Manual shutter is the default; automatic capture is not an assumed requirement.
- Proprietary CamScanner algorithms, code and graphics are not part of this independently implemented Flutter design.

## What “verified” means

The latest verified baseline `0.5.18+32` completed native tests, `flutter analyze`, `flutter test` and release APK building in [GitHub Actions #42541619956](https://github.com/faria2177/DS-Fult/actions/runs/42541619956). The new `0.5.19+33` PDF-to-images import requires fresh CI and real-device tests. Automated checks **do not** prove live CameraX behavior, Android PDF picker permissions, PDFium fidelity, external sharing or screenshot identity on a physical phone.

## Reporting a newly observed issue

Supply the app version, device/Android version, precise interaction steps, expected/actual result and a short recording or redacted log. Add a confirmed regression to [BUGS.md](BUGS.md); add a reproducible remediation task to [TODO.md](TODO.md). Keep personal ID cards and private scanned data out of public GitHub issues.
