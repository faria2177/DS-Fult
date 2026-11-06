# DocScanner — Flutter (DS-Fult)

Local-first Android document scanner with an original DS-branded, CamScanner-inspired interface.
The app does **not** include CamScanner's proprietary code, artwork, cloud services or trademarks.

## Implemented in this first foundation

- Flutter Material 3 UI: Home, Files, Scan, Tools, Me; light and dark modes.
- Real Camera preview, HD capture, flash, gallery import and multi-page documents.
- Local document library, persistent folders, rename/move/delete and image previews.
- Manual four-corner perspective crop with a homography transform.
- Original, Auto, Enhance, Magic Color, Grayscale, B&W image filters.
- ID Card / Driver License / Bank Card front-and-back workflows with a **hard two-image maximum**, including the gallery picker limit.
- Single A4 PDF with both sides of a card; standard multi-page PDF for documents.
- Share PDF/images, print via Android system print service.
- On-device **Latin-script** OCR, editable extracted text, copy/share TXT, and custom **DS AI PROSINESS** processing animation.
- GitHub Actions release APK builds for ARM32, ARM64 and x86_64.

## Not yet implemented

The scanner border is currently a *guide*, not computer-vision contour tracking. Automatic edge detection/auto capture, image-region AI text replacement, Bengali OCR model packaging, PDF text inpainting, Office conversions, smart erase, watermark, signatures, merge/reorder/lock/compress are planned. The Tools screen clearly reports unimplemented actions; it does not pretend they work. This version is a real foundation, **not** feature or quality parity with CamScanner.

## Requirements

- Flutter **3.47.4** (Dart 3.13.3)
- Android SDK and Java 17
- Android min SDK 24, compile with the SDK Flutter selects

## First checkout / run

```bash
git clone https://github.com/faria2177/DS-Fult.git
cd DS-Fult
bash tool/setup_android.sh
flutter pub get
flutter analyze
flutter test
flutter run
```

The first setup uses `flutter create` to generate the official version-matched `android/` host template. The repository intentionally does not duplicate this template; CI generates it on each build. Camera/ML Kit functionality requires a physical Android device. Edit Text uses ML Kit's on-device Latin model and sends no images to a remote AI endpoint.

## APK downloads

Open the repository's **Actions → Android APK → latest successful run → Artifacts → DocScanner-Android-APKs**. Release APK files will be in that ZIP after the workflow has succeeded.

## Architecture

```text
lib/main.dart
  src/app.dart                 App, theme preferences
  src/screens/home_shell.dart  Home / Files / Tools / Me
  src/screens/camera_screen.dart  Camera + gallery picker
  src/screens/id_card_screen.dart Front / back capture
  src/screens/crop_screen.dart Four-corner crop editor
  src/screens/document_screen.dart Page editing / exports
  src/screens/edit_text_screen.dart OCR + editable text
  src/services/image_processor.dart Image filters / perspective
  src/services/document_export.dart PDF/print/share
  src/storage/document_store.dart Local image+JSON library
```

The full-resolution original image is kept separate from processed copies; the OCR text is stored in the local document index. The first release keeps deleted image files for potential recovery, so future storage cleanup must be implemented separately.

Developed for **DocScanner / DS** by Md Jahidul Islam.
