import 'dart:typed_data';

import 'package:docscanner/src/models.dart';
import 'package:docscanner/src/screens/office_conversion_screen.dart';
import 'package:docscanner/src/screens/word_review_screen.dart';
import 'package:docscanner/src/screens/excel_review_screen.dart';
import 'package:docscanner/src/screens/pdf_tools_screen.dart';
import 'package:docscanner/src/screens/signature_screen.dart';
import 'package:docscanner/src/services/xlsx_export.dart';
import 'package:docscanner/src/services/ai_document_vision_gateway.dart';
import 'package:docscanner/src/services/ai_text_gateway.dart';
import 'package:docscanner/src/storage/document_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _VisionFake implements AiDocumentVisionEngine {
  int calls = 0;
  AiDocumentFormat? lastFormat;
  @override
  Future<AiTextConfig?> activeConfiguration() async => const AiTextConfig(
    providerId: 'gemini', providerName: 'Google AI Studio',
    modelId: 'gemini-test');

  @override
  Future<String> transcribe({required AiTextConfig config,
      required AiDocumentFormat format, required Uint8List jpeg}) async {
    calls++;
    lastFormat = format;
    return format == AiDocumentFormat.word
        ? 'Match schedule\nTeam\tScore\nDhaka\t4'
        : 'Team\tScore\nDhaka\t4';
  }
}

final _document = ScanDocument(
  id: 'doc', name: 'Financial Statement',
  createdAt: DateTime(2026, 11, 9),
  pages: const [
    ScanPage(id: 'p1', path: '/missing-p1.png',
      originalPath: '/missing-p1.png',
      recognizedText: 'Name  Amount\nJahid  200'),
    ScanPage(id: 'p2', path: '/missing-p2.png',
      originalPath: '/missing-p2.png',
      recognizedText: 'Month  Total\nNov  300'),
  ],
);

class _PdfStore extends DocumentStore {
  @override
  ScanDocument? byId(String id) => id == _document.id ? _document : null;
}

void main() {
  testWidgets('AI Word vision is never called before explicit image consent',
      (tester) async {
    final vision = _VisionFake();
    await tester.pumpWidget(MaterialApp(home: OfficeConversionScreen(
      document: _document, toExcel: false, visionEngine: vision,
      prepareAiPage: (_) async => Uint8List.fromList([1, 2, 3]),
    )));
    await tester.tap(find.byKey(const Key('office-primary-action')));
    await tester.pumpAndSettle();
    expect(find.text('Improve accuracy with AI vision?'), findsOneWidget);
    expect(vision.calls, 0);
    await tester.tap(find.byKey(const Key('office-ai-cancel')));
    await tester.pumpAndSettle();
    expect(vision.calls, 0);
    await tester.tap(find.byKey(const Key('office-primary-action')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('office-ai-send')));
    await tester.pumpAndSettle();
    expect(vision.calls, 2);
    expect(vision.lastFormat, AiDocumentFormat.word);
    expect(find.byType(WordReviewScreen), findsOneWidget);
    expect(find.textContaining('Match schedule'), findsOneWidget);
  });

  testWidgets('Excel AI vision preserves actual tab-delimited rows',
      (tester) async {
    final vision = _VisionFake();
    await tester.pumpWidget(MaterialApp(home: OfficeConversionScreen(
      document: _document, toExcel: true, visionEngine: vision,
      prepareAiPage: (_) async => Uint8List.fromList([1, 2, 3]),
    )));
    await tester.tap(find.byKey(const Key('office-primary-action')));
    await tester.pumpAndSettle();
    expect(vision.calls, 0);
    await tester.tap(find.byKey(const Key('office-ai-send')));
    await tester.pumpAndSettle();
    expect(vision.calls, 2);
    expect(vision.lastFormat, AiDocumentFormat.excel);
    expect(find.byType(ExcelReviewScreen), findsOneWidget);
    expect(find.text('Dhaka'), findsWidgets);
  });

  testWidgets('Choosing local conversion sends no scanned images',
      (tester) async {
    final vision = _VisionFake();
    var localCalls = 0;
    await tester.pumpWidget(MaterialApp(home: OfficeConversionScreen(
      document: _document, toExcel: false, visionEngine: vision,
      localRecognizer: (_, _) async {
        localCalls++;
        return ['Local recognition', 'Second page'];
      },
    )));
    await tester.tap(find.byKey(const Key('office-primary-action')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('office-ai-local')));
    await tester.pumpAndSettle();
    expect(vision.calls, 0);
    expect(localCalls, 1);
    expect(find.byType(WordReviewScreen), findsOneWidget);
    expect(find.textContaining('Local recognition'), findsOneWidget);
  });
  testWidgets('Word conversion offers page selection, OCR language and preview',
      (tester) async {
    await tester.pumpWidget(MaterialApp(home: OfficeConversionScreen(
      document: _document, toExcel: false,
    )));
    await tester.pump();
    expect(find.text('Convert to editable Word'), findsOneWidget);
    expect(find.text('2 selected'), findsOneWidget);
    expect(find.text('English / Latin'), findsOneWidget);
    expect(find.text('বাংলা / Bengali'), findsOneWidget);
    expect(find.text('Recognize & Preview'), findsOneWidget);
    await tester.tap(find.byKey(const Key('office-page-p2')));
    await tester.pump();
    expect(find.text('1 selected'), findsOneWidget);
    await tester.tap(find.text('বাংলা / Bengali'));
    await tester.pump();
    expect(find.text('1 selected'), findsOneWidget);
  });

  testWidgets('Excel conversion starts with an editable-table workflow',
      (tester) async {
    await tester.pumpWidget(MaterialApp(home: OfficeConversionScreen(
      document: _document, toExcel: true,
    )));
    await tester.pump();
    expect(find.text('Convert to editable Excel'), findsOneWidget);
    expect(find.text('Recognize & Preview'), findsOneWidget);
    expect(find.textContaining('Always review names, dates and numbers'),
        findsOneWidget);
  });

  test('Excel preview uses the exact same column boundaries as export', () {
    expect(XlsxExport.cellsFromLine('Name\tAmount'), ['Name', 'Amount']);
    expect(XlsxExport.cellsFromLine('বাংলা  25%  100/-'),
        ['বাংলা', '25%', '100/-']);
    expect(XlsxExport.cellsFromLine('Heading alone'), ['Heading alone']);
  });

  testWidgets('Edit PDF shows real page editing and exporting operations',
      (tester) async {
    await tester.pumpWidget(MaterialApp(home: PdfToolsScreen(
      store: _PdfStore(), documentId: _document.id,
    )));
    await tester.pump();
    expect(find.text('Edit PDF'), findsOneWidget);
    expect(find.text('Edit Page'), findsOneWidget);
    expect(find.text('Sign'), findsOneWidget);
    expect(find.byKey(const Key('pdf-page-p1')), findsOneWidget);
    expect(find.byKey(const Key('pdf-page-p2')), findsOneWidget);
    await tester.tap(find.byKey(const Key('pdf-page-p2')));
    await tester.pump();
    await tester.drag(find.byType(ListView).first, const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(find.text('Watermark'), findsOneWidget);
    expect(find.text('Rotate Pages'), findsOneWidget);
    expect(find.text('Extract Pages'), findsOneWidget);
    await tester.drag(find.byType(ListView).first, const Offset(0, -450));
    await tester.pumpAndSettle();
    expect(find.text('Share PDF'), findsOneWidget);
  });

  testWidgets('Sign PDF exposes ink palette, pen size and explicit Apply',
      (tester) async {
    await tester.pumpWidget(MaterialApp(home: SignatureScreen(
      store: _PdfStore(), documentId: _document.id, pageId: 'p1',
    )));
    expect(find.text('Sign PDF'), findsOneWidget);
    expect(find.text('Add your signature'), findsOneWidget);
    expect(find.text('Ink color'), findsOneWidget);
    expect(find.text('Pen size'), findsOneWidget);
    expect(find.text('Apply Signature'), findsOneWidget);
    expect(find.byType(Slider), findsOneWidget);
  });
}
