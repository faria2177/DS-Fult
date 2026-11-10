import 'package:docscanner/src/screens/gallery_import_review_screen.dart';
import 'package:docscanner/src/services/image_processor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('CamScanner-style Select Photo review exposes import options',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: GalleryImportReviewScreen(
        imagePaths: ['/nonexistent/photo1.jpg', '/nonexistent/photo2.jpg'],
        initialFilter: ScanFilter.original,
      ),
    ));

    expect(find.text('Select Photo'), findsOneWidget);
    expect(find.text('Import (2)'), findsOneWidget);
    expect(find.text('Enhance'), findsOneWidget);
    expect(tester.widget<Checkbox>(find.byKey(const Key('import-auto-crop')))
        .value, isTrue);

    await tester.tap(find.byKey(const Key('import-photo-0')));
    await tester.pump();
    expect(find.text('Import (1)'), findsOneWidget);

    await tester.tap(find.byKey(const Key('import-auto-crop')));
    await tester.pump();
    expect(tester.widget<Checkbox>(find.byKey(const Key('import-auto-crop')))
        .value, isFalse);

    await tester.tap(find.text('View selected'));
    await tester.pump();
    expect(find.byKey(const Key('import-photo-0')), findsNothing);
    expect(find.byKey(const Key('import-photo-1')), findsOneWidget);
  });

  testWidgets('Import with Auto Crop disabled retains each selected source',
      (tester) async {
    GalleryImportResult? returned;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) =>
      Scaffold(body: TextButton(onPressed: () async {
        returned = await Navigator.of(context).push<GalleryImportResult>(
          MaterialPageRoute(builder: (_) => const GalleryImportReviewScreen(
            imagePaths: ['/nonexistent/a.jpg', '/nonexistent/b.jpg'],
            initialAutoCrop: false,
            initialFilter: ScanFilter.original,
          )),
        );
      }, child: const Text('Open import')),
    ))));

    await tester.tap(find.text('Open import'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Import (2)'));
    await tester.pumpAndSettle();

    expect(returned?.sourcePaths, ['/nonexistent/a.jpg', '/nonexistent/b.jpg']);
    expect(returned?.paths, ['/nonexistent/a.jpg', '/nonexistent/b.jpg']);
    expect(returned?.needsReview, 0);
  });
}
