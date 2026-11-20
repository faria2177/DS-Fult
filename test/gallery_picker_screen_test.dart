import 'dart:typed_data';

import 'package:docscanner/src/screens/gallery_import_review_screen.dart';
import 'package:docscanner/src/screens/gallery_picker_screen.dart';
import 'package:docscanner/src/services/gallery_asset_source.dart';
import 'package:docscanner/src/services/image_processor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeLibrary implements GalleryAssetSource {
  _FakeLibrary(this.count);

  @override
  final int count;

  @override
  Future<Uint8List?> thumbnail(int index) async => null;

  @override
  Future<String?> filePath(int index) async => '/nonexistent/photo$index.jpg';
}

Widget _host(Widget child) => MaterialApp(home: child);

void main() {
  testWidgets('Select Photo grid numbers picks in order and counts them',
      (tester) async {
    await tester.pumpWidget(_host(GalleryPickerScreen(
      source: _FakeLibrary(6), initialFilter: ScanFilter.original)));
    await tester.pump();

    expect(find.text('Select Photo'), findsOneWidget);
    expect(find.text('Import(0)'), findsOneWidget);
    expect(find.text('Auto Crop'), findsOneWidget);
    expect(tester.widget<Checkbox>(
        find.byKey(const Key('gallery-auto-crop'))).value, isTrue);
    expect(tester.widget<FilledButton>(
        find.byKey(const Key('gallery-import'))).onPressed, isNull);

    await tester.tap(find.byKey(const Key('gallery-select-2')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('gallery-select-0')));
    await tester.pump();
    expect(find.text('Import(2)'), findsOneWidget);
    // Photo 2 was picked first, photo 0 second.
    expect(find.descendant(of: find.byKey(const Key('gallery-select-2')),
        matching: find.text('1')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('gallery-select-0')),
        matching: find.text('2')), findsOneWidget);

    await tester.tap(find.byKey(const Key('gallery-select-2')));
    await tester.pump();
    expect(find.text('Import(1)'), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('gallery-select-0')),
        matching: find.text('1')), findsOneWidget);
  });

  testWidgets('tapping a photo opens the n/total preview with Select',
      (tester) async {
    await tester.pumpWidget(_host(GalleryPickerScreen(
      source: _FakeLibrary(6), initialFilter: ScanFilter.original)));
    await tester.pump();

    await tester.tap(find.byKey(const Key('gallery-photo-1')));
    await tester.pumpAndSettle();
    expect(find.text('2/6'), findsOneWidget);
    expect(find.text('Select'), findsOneWidget);

    await tester.tap(find.byKey(const Key('gallery-preview-select')));
    await tester.pump();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Import(1)'), findsOneWidget);
  });

  testWidgets('selection limit is enforced', (tester) async {
    await tester.pumpWidget(_host(GalleryPickerScreen(
      source: _FakeLibrary(6), maxSelection: 2,
      initialFilter: ScanFilter.original)));
    await tester.pump();
    for (final index in [0, 1, 2]) {
      await tester.tap(find.byKey(Key('gallery-select-$index')));
      await tester.pump();
    }
    expect(find.text('Import(2)'), findsOneWidget);
  });

  testWidgets('Import returns straight to the caller without a corner dialog',
      (tester) async {
    GalleryImportResult? returned;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) =>
      Scaffold(body: TextButton(onPressed: () async {
        returned = await Navigator.of(context).push<GalleryImportResult>(
          MaterialPageRoute(builder: (_) => GalleryPickerScreen(
            source: _FakeLibrary(4),
            initialAutoCrop: false,
            initialFilter: ScanFilter.original,
          )),
        );
      }, child: const Text('Open')),
    ))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('gallery-select-3')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('gallery-select-1')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('gallery-import')));
    await tester.pumpAndSettle();

    expect(find.text('Open'), findsOneWidget);
    expect(returned?.sourcePaths,
        ['/nonexistent/photo3.jpg', '/nonexistent/photo1.jpg']);
    expect(returned?.paths,
        ['/nonexistent/photo3.jpg', '/nonexistent/photo1.jpg']);
  });

  testWidgets('limited photo access is explained and Browse imports others',
      (tester) async {
    var allowAll = 0;
    GalleryImportResult? returned;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) =>
      Scaffold(body: TextButton(onPressed: () async {
        returned = await Navigator.of(context).push<GalleryImportResult>(
          MaterialPageRoute(builder: (_) => GalleryPickerScreen(
            source: _FakeLibrary(2),
            initialAutoCrop: false,
            initialFilter: ScanFilter.original,
            limitedAccess: true,
            onAllowAll: () async => allowAll++,
            onBrowse: () async => ['/nonexistent/other.jpg'],
          )),
        );
      }, child: const Text('Open')),
    ))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('gallery-limited-notice')), findsOneWidget);
    await tester.tap(find.text('Allow all'));
    await tester.pump();
    expect(allowAll, 1);

    await tester.tap(find.byKey(const Key('gallery-browse')));
    await tester.pumpAndSettle();
    expect(returned?.paths, ['/nonexistent/other.jpg']);
  });

  testWidgets('full photo access shows no notice', (tester) async {
    await tester.pumpWidget(_host(GalleryPickerScreen(
      source: _FakeLibrary(2), initialFilter: ScanFilter.original)));
    await tester.pump();
    expect(find.byKey(const Key('gallery-limited-notice')), findsNothing);
    expect(find.byKey(const Key('gallery-browse')), findsNothing);
  });

  testWidgets('preview has an Import button that imports the shown photo',
      (tester) async {
    GalleryImportResult? returned;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) =>
      Scaffold(body: TextButton(onPressed: () async {
        returned = await Navigator.of(context).push<GalleryImportResult>(
          MaterialPageRoute(builder: (_) => GalleryPickerScreen(
            source: _FakeLibrary(4),
            initialAutoCrop: false,
            initialFilter: ScanFilter.original,
          )),
        );
      }, child: const Text('Open')),
    ))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('gallery-photo-2')));
    await tester.pumpAndSettle();
    expect(find.text('3/4'), findsOneWidget);
    expect(find.text('Import(1)'), findsOneWidget);
    await tester.tap(find.byKey(const Key('gallery-preview-import')));
    await tester.pumpAndSettle();
    expect(returned?.sourcePaths, ['/nonexistent/photo2.jpg']);
  });
}
