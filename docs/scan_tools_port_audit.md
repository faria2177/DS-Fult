# DocScanner scan and Tools integration audit

Reference archive: `DS-p-codex-scan-crop-preview-20261103.zip` (native Android / Kotlin / Compose).
Target: `DS-Fult` (Flutter / Dart, Android-specific `third_party/doclens`).

## Scanner: what was actually reused

The reference scanner is **not a Flutter plugin**. Its UI/camera code depends on
Jetpack Compose, CameraX and the native Android application's navigation.
Copying its activities into `lib/` would not work.

The following algorithm files are portable Kotlin and were reused under
`third_party/doclens/android/src/main/kotlin/com/docscan/scanner/`:

| Reference file | Behavior |
| --- | --- |
| `DocumentBoundaryDetector.kt` | Multi-pass contour detection (CLAHE/Canny/adaptive threshold/color saturation), Hough-line fallback and weighted candidate scoring |
| `ContourDetector.kt` | Geometry, convex quadrilateral extraction and rejection of implausible contours |
| `CornerRefiner.kt` | Precision adjustment of the four detected corners |
| `DocumentDetectionResult.kt` | Boundary coordinates, confidence and detection metadata |

`OpenCvBoundaryAdapter.kt` bridges the above into Doclens's normalized `Quad`:

- Camera preview: CameraX Y plane -> grayscale RGBA OpenCV Mat -> four normalized corners -> existing overlay/temporal smoother. No automatic shutter.
- Captured stills and gallery images: full-color bitmap -> OpenCV -> detected crop polygon -> existing perspective warp; the original bitmap-backed detector remains fallback.
- Native library loading: the OpenCV Maven Android AAR (`org.opencv:opencv:4.10.0`) provides its own JNI binaries. No private CamScanner `.so` is required for this pipeline.
- If OpenCV cannot initialize or does not find a reliable page, Doclens retains its previous luma-based detection. Both detection and processing run offline.

**Known limitation**: the CameraX preview currently supplies its Y plane, so
the reference detector's color-saturation branch is useful on captured still
images but unavailable on live preview. Actual corner stability and capture
quality still require testing with the user's specific Android device, under
real lighting and against A4/ID cards.

## Tools UI audit and first functional ports

The reference HomeScreen groups **26** actions into four categories:

- **Scan (5)**: ID Cards, Extract Text, Passport Photo Maker, Photo Translation, Scan Code.
- **Convert (7)**: Merge PDF, Image to PDF, Text to PDF, To Word, To Excel, PDF to Images, PDF to Long Image.
- **Edit (11)**: Edit PDF, BG Remover, Image Resizer, Split PDF, Sign, Add Watermark, Extract PDF Pages, Reorder Pages, Rotate PDF, Lock, Compress.
- **Utilities (3)**: AI Chat, Print, Create QR Code.

The Flutter UI also includes pre-existing or previously requested actions:
Scan, Mega Scan, Long Document, Import Images, Import File, Driver License,
Bank Card, Edit Text, Smart Erase, Erase Marks, Restore Photo and To PPT.

| Status | Tools |
| --- | --- |
| Existing functional workflows | Scan (manual shutter), Mega Scan, Long Document, ID Cards/Driver License/Bank Card, Import Images, Extract Text/Edit Text via document toolbar, Merge PDF, Image to PDF through import/export, Edit PDF (page tools), Add Watermark, Extract PDF Pages, Reorder Pages, Rotate PDF via document toolbar, Compress PDF, Print |
| Added functional workflows | Text to PDF (Latin-script text, share PDF), PDF to Images (export stored scanned page images), PDF to Long Image (join image-backed pages vertically, memory bounded), Image Resizer (select/import and share size-limited JPEG) |
| Currently routed to PDF page tools | Split PDF (extract selected page subset, not an arbitrary imported-PDF splitter) |
| Exposed clearly as not yet implemented | Import File (external PDF), Passport Photo Maker, Photo Translation, Scan Code, To Word, To Excel, To PPT, BG Remover, Sign, Smart Erase, Erase Marks, Restore Photo, Lock PDF, AI Chat, Create QR Code |

**Scope distinction**: reference screens are **not automatically executable**
inside Flutter. Some need their own Dart UI/processing engine, on-device AI
models, a PDF renderer or document format writers. An option is not considered
working merely because it appears in the tool grid. Private CamScanner JNI
binaries checked into the repository are not referenced by this implementation,
and their use should be reviewed separately for license/packaging compatibility.
