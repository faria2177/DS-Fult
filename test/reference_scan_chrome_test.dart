import 'package:doclens/doclens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('framed scanner keeps the preview separate from controls',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var captured = 0;
    bool? switchedToBatch;
    var openedIds = 0;
    final settings = ReferenceScanSettings();
    addTearDown(settings.dispose);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ReferenceScanChrome(
          preview: const ColoredBox(color: Colors.red),
          flashMode: FlashMode.off,
          batchMode: false,
          pageCount: 0,
          capturing: false,
          accent: const Color(0xFF15BFA9),
          settings: settings,
          onClose: () {},
          onFlash: () {},
          onCapture: () => captured++,
          onBatchChanged: (value) => switchedToBatch = value,
          onFinishBatch: () {},
          onImportFiles: () {},
          onImportImages: () {},
          onIdCards: () => openedIds++,
        ),
      ),
    ));

    expect(find.text('Single'), findsOneWidget);
    expect(find.text('Batch'), findsOneWidget);
    expect(find.text('Scan'), findsOneWidget);
    expect(find.text('ID Cards'), findsOneWidget);
    expect(find.text('Import Files'), findsOneWidget);
    expect(find.text('Import\nImages'), findsOneWidget);

    final view = tester.getRect(find.byKey(const Key('reference-preview')));
    expect(view.top, greaterThan(60));
    expect(view.bottom, lessThan(710));

    await tester.tap(find.byKey(const Key('reference-shutter')));
    await tester.pump();
    expect(captured, 1);

    await tester.tap(find.text('Batch'));
    expect(switchedToBatch, isTrue);

    await tester.tap(find.text('ID Cards'));
    expect(openedIds, 1);
  });

  testWidgets('video effect, HD and settings menus update real preferences',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final settings = ReferenceScanSettings();
    addTearDown(settings.dispose);
    var openedMore = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body:
      ReferenceScanChrome(
        preview: const ColoredBox(color: Colors.black),
        flashMode: FlashMode.off,
        batchMode: false,
        pageCount: 0,
        capturing: false,
        accent: const Color(0xFF00B69B),
        settings: settings,
        cameraModes: const [
          ScanCameraMode(4064, 3048),
          ScanCameraMode(4032, 3024),
          ScanCameraMode(3840, 2160),
          ScanCameraMode(3264, 2448),
          ScanCameraMode(2560, 1440),
        ],
        onClose: () {},
        onFlash: () {},
        onCapture: () {},
        onBatchChanged: (_) {},
        onFinishBatch: () {},
        onMoreSettings: () => openedMore++,
      ),
    )));

    await tester.tap(find.byTooltip('Effects'));
    await tester.pump();
    expect(find.text('Magic Pro'), findsOneWidget);
    expect(find.text('No Watermark'), findsOneWidget);
    expect(find.text('No Handwriting'), findsOneWidget);
    await tester.tap(find.byKey(const Key('scan-effect-invert')));
    await tester.pump();
    expect(settings.effect, ScanEffectPreset.invert);

    await tester.tap(find.text('HD'));
    await tester.pump();
    expect(find.text('List All Modes ⌄'), findsOneWidget);
    await tester.tap(find.text('List All Modes ⌄'));
    await tester.pump();
    expect(find.text('4M (2560x1440)'), findsOneWidget);
    await tester.tap(find.text('4M (2560x1440)'));
    expect(settings.resolution, '2560x1440');

    await tester.tap(find.byTooltip('Scanner Settings'));
    await tester.pump();
    expect(find.text('Auto Capture'), findsOneWidget);
    expect(find.text('Spirit Level'), findsOneWidget);
    await tester.tap(find.text('More Settings'));
    expect(openedMore, 1);
  });
}
