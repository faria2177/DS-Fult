import 'package:docscanner/src/models.dart';
import 'package:docscanner/src/screens/pdf_to_images_screen.dart';
import 'package:docscanner/src/screens/video_tool_source_picker.dart';
import 'package:docscanner/src/storage/document_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _PdfStore extends DocumentStore {
  @override
  List<ScanDocument> get documents => [document];
}

final document = ScanDocument(
  id: 'pdf-scan', name: 'Document Pages', createdAt: DateTime(2026, 11, 9),
  pages: const [
    ScanPage(id: 'one', path: '/missing-one.png',
        originalPath: '/missing-one.png'),
    ScanPage(id: 'two', path: '/missing-two.png',
        originalPath: '/missing-two.png'),
  ],
);

void main() {
  testWidgets('PDF source picker provides actual device PDF option',
      (tester) async {
    await tester.pumpWidget(MaterialApp(home: VideoToolSourcePicker(
      store: _PdfStore(), title: 'PDF to Images',
      description: 'Select PDF', icon: Icons.collections_outlined,
      allowPdf: true, allowGallery: true,
    )));
    expect(find.text('PDF File'), findsOneWidget);
    expect(find.text('Gallery'), findsOneWidget);
    expect(find.text('Document Pages'), findsOneWidget);
  });

  testWidgets('PDF to Images select-all, deselect and format controls',
      (tester) async {
    await tester.pumpWidget(MaterialApp(home: PdfToImagesScreen(
        document: document, store: _PdfStore())));
    await tester.pump();
    expect(find.text('2/2 selected'), findsOneWidget);
    expect(find.text('Save as New'), findsOneWidget);
    expect(find.text('Share Images'), findsOneWidget);
    expect(find.text('Save to Gallery'), findsOneWidget);

    await tester.tap(find.text('Deselect All'));
    await tester.pump();
    expect(find.text('0/2 selected'), findsOneWidget);
    final shareDisabled = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Share Images'));
    expect(shareDisabled.onPressed, isNull);

    await tester.tap(find.text('Select All'));
    await tester.pump();
    expect(find.text('2/2 selected'), findsOneWidget);
    await tester.tap(find.text('PNG'));
    await tester.pump();
    final pngChip = tester.widget<ChoiceChip>(
        find.widgetWithText(ChoiceChip, 'PNG'));
    expect(pngChip.selected, true);
  });
}
