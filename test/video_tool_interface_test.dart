import 'dart:typed_data';

import 'package:docscanner/src/models.dart';
import 'package:docscanner/src/screens/video_tool_source_picker.dart';
import 'package:docscanner/src/screens/video_tool_style.dart';
import 'package:docscanner/src/services/image_text_processor.dart';
import 'package:docscanner/src/storage/document_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

class _PickerStore extends DocumentStore {
  @override
  List<ScanDocument> get documents => [
    ScanDocument(id: 'a', name: 'Front Page',
      createdAt: DateTime(2026, 11, 8), pages: const [
        ScanPage(id: 'one', path: '/missing-1.png',
          originalPath: '/missing-1.png'),
      ]),
    ScanDocument(id: 'b', name: 'Back Page',
      createdAt: DateTime(2026, 11, 8), pages: const [
        ScanPage(id: 'two', path: '/missing-2.png',
          originalPath: '/missing-2.png'),
      ]),
  ];
}

void main() {
  testWidgets('video picker can select two source documents for merge',
      (tester) async {
    final store = _PickerStore();
    await tester.pumpWidget(MaterialApp(home: VideoToolSourcePicker(
      store: store, title: 'Merge Files',
      description: 'Merge files in seconds to save time and effort.',
      icon: Icons.merge_type, multiSelect: true,
    )));
    await tester.pump();
    expect(find.text('Merge Files'), findsOneWidget);
    expect(find.text('Merge (0)'), findsOneWidget);
    await tester.tap(find.text('Front Page'));
    await tester.pump();
    expect(find.text('Merge (1)'), findsOneWidget);
    await tester.tap(find.text('Back Page'));
    await tester.pump();
    expect(find.text('Merge (2)'), findsOneWidget);
    expect(find.byType(Checkbox), findsNWidgets(2));
  });

  testWidgets('Import File shows PDF/image import without existing-doc picker',
      (tester) async {
    var pdfPickerOpened = false;
    const channel = MethodChannel('doclens/methods');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel, (call) async {
        if (call.method == 'pickPdfFile') pdfPickerOpened = true;
        return null; // User cancels the native document picker.
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    await tester.pumpWidget(MaterialApp(home: VideoToolSourcePicker(
      store: _PickerStore(), title: 'Import File',
      description: 'Import a PDF or images from your phone, offline.',
      icon: Icons.upload_file_outlined,
      allowPdf: true, importsOnly: true,
    )));
    await tester.pump();
    expect(find.text('Import File'), findsOneWidget);
    expect(find.text('Images'), findsOneWidget);
    expect(find.text('PDF File'), findsOneWidget);
    expect(find.text('Select from This App'), findsNothing);
    expect(find.text('Front Page'), findsNothing);
    expect(find.text('Back Page'), findsNothing);
    await tester.tap(find.text('PDF File'));
    await tester.pump();
    expect(pdfPickerOpened, isTrue);
    expect(find.text('Import File'), findsOneWidget);
  });

  testWidgets('reference-video tool bottom bar keeps close and done controls',
      (tester) async {
    var saved = false;
    var cancelled = false;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body:
      VideoToolBottomBar(title: 'Add Watermark',
        onCancel: () => cancelled = true,
        onDone: () => saved = true,
      ),
    )));
    expect(find.text('Add Watermark'), findsOneWidget);
    await tester.tap(find.byTooltip('Done'));
    expect(saved, isTrue);
    await tester.tap(find.byTooltip('Cancel'));
    expect(cancelled, isTrue);
  });

  test('Smart Erase brush paints over selected marks offline', () async {
    final image = img.Image(width: 80, height: 80);
    img.fill(image, color: img.ColorRgb8(245, 245, 245));
    for (var y = 30; y < 51; y++) {
      for (var x = 30; x < 51; x++) {
        image.setPixelRgb(x, y, 20, 20, 20);
      }
    }
    final Uint8List encoded = Uint8List.fromList(img.encodePng(image));
    final output = await ImageTextProcessor.eraseBrush(encoded,
      normalizedPoints: const [Offset(.5, .5)], normalizedRadius: .2);
    final result = img.decodePng(output)!;
    expect(result.getPixel(40, 40).r, greaterThan(20));
  });
}
