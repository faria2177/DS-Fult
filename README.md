# DocScanner — Flutter (DS-Fult)

Local-first Android document scanner with an original DS-branded, CamScanner-inspired interface.
The app does **not** include CamScanner's proprietary code, artwork, cloud services or trademarks.

## Implemented in v0.2 (work in progress)

- Flutter Material 3 UI: Home, Files, Scan, Tools, Me; light and dark modes.
- Native live document corner tracking, auto-capture after a stability/sharpness check,
  dewarp and adjustable review using the MIT-licensed `doclens` engine; manual
  camera remains available for devices where the detector is unsuccessful.
- HD camera capture, flash, gallery import and multi-page documents.
- Local document library, persistent folders, rename/move/delete and image previews.
- Manual four-corner perspective crop with a homography transform.
- Original, Auto, Enhance, **Shadow Free**, Magic Color, Grayscale, B&W filters.
  Auto/Enhance/Shadow Free now estimate local illumination to lift dark paper areas.
- ID Card / Driver License / Bank Card front-and-back workflows with a **hard two-image maximum**, including the gallery picker limit.
- Single A4 PDF with both sides of a card; standard multi-page PDF for documents.
- Share PDF/images, print via Android system print service.
- On-device **English/Latin OCR** plus **offline Bengali OCR** using the BSD-licensed
  Tesseract plugin and `tessdata_fast` Bengali language model (bundled in APK).
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
  src/services/image_text_processor.dart Pixel-level text replacement
  src/services/document_export.dart PDF/print/share
  src/storage/document_store.dart Local image+JSON library
```

The full-resolution original image is kept separate from processed copies; the OCR text is stored in the local document index. The first release keeps deleted image files for potential recovery, so future storage cleanup must be implemented separately.

Developed for **DocScanner / DS** by Md Jahidul Islam.
