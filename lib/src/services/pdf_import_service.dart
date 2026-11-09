import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';

import '../models.dart';
import '../storage/document_store.dart';

/// Rasterize a PDF selected through Android's system document picker into
/// editable local image pages. The file chosen by the user remains untouched;
/// the Android bridge supplies a separate cache copy for rasterization.
class PdfImportService {
  PdfImportService._();

  static Future<ScanDocument> importPdf(
      String cachedPdfPath, DocumentStore store,
      {int maxPages = 80}) async {
    if (maxPages < 1) throw ArgumentError.value(maxPages, 'maxPages');
    final source = File(cachedPdfPath);
    if (!await source.exists()) {
      throw const FileSystemException('Selected PDF is not available');
    }
    final bytes = await source.readAsBytes();
    if (bytes.length < 5 ||
        String.fromCharCodes(bytes.take(5)) != '%PDF-') {
      throw const FormatException('The selected file is not a valid PDF.');
    }
    final temporary = await getTemporaryDirectory();
    final pagesDirectory = Directory(p.join(temporary.path,
        'docscanner_pdf_pages_${DateTime.now().microsecondsSinceEpoch}'));
    await pagesDirectory.create();
    final paths = <String>[];
    try {
      await for (final page in Printing.raster(bytes, dpi: 150)) {
        if (paths.length >= maxPages) {
          throw FormatException('This conversion supports up to '
              '$maxPages pages at a time. Split the PDF to continue.');
        }
        final png = await page.toPng();
        final file = File(p.join(pagesDirectory.path,
            'page_${(paths.length + 1).toString().padLeft(3, '0')}.png'));
        await file.writeAsBytes(png, flush: true);
        paths.add(file.path);
      }
      if (paths.isEmpty) {
        throw const FormatException('No visible pages in this PDF.');
      }
      return await store.createFromPaths(paths,
          name: 'Imported PDF (${paths.length} pages)');
    } finally {
      // Delete only the private raster staging directory created above.
      // The store has already copied successful imports into its own library.
      if (await pagesDirectory.exists()) {
        await pagesDirectory.delete(recursive: true);
      }
    }
  }
}
