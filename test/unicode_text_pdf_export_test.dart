import 'dart:convert';

import 'package:docscanner/src/services/unicode_text_pdf_export.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Bengali/Unicode OCR text exports as a valid local PDF', () async {
    final pdf = await UnicodeTextPdfExport.build([
      'ঢাকা ও খুলনা\nMatch schedule\n১২:৩০ – ০২:১০',
    ]);
    expect(latin1.decode(pdf.sublist(0, 5)), '%PDF-');
    expect(pdf.length, greaterThan(1500));
  });
}
