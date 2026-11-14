import 'package:doclens/doclens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Front capture shows Back 1/2 without allowing premature Done',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final settings = ReferenceScanSettings();
    addTearDown(settings.dispose);
    var captures = 0;
    var imported = 0;
    var finished = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body:
      ReferenceIdCardChrome(
        preview: const ColoredBox(color: Colors.black),
        label: 'ID Card',
        side: 'Back',
        portraitGuide: false,
        accent: const Color(0xFF00B69B),
        flashMode: FlashMode.off,
        capturing: false,
        settings: settings,
        pagesCaptured: 1,
        waitingForBack: true,
        onClose: () {},
        onFlash: () {},
        onCapture: () => captures++,
        onImportImages: () => imported++,
        onFinishBatch: () => finished++,
      ),
    )));
    expect(find.text('Back'), findsOneWidget);
    expect(find.text('1/2 captured'), findsOneWidget);
    final action = tester.widget<InkWell>(
        find.byKey(const Key('card-right-action')));
    expect(action.onTap, isNull);
    await tester.tap(find.byKey(const Key('card-shutter')));
    await tester.pump();
    expect(captures, 1);
    expect(imported, 0);
    expect(finished, 0);
  });

  test('quick ID capture is explicit, not enabled for other scan modes', () {
    const regular = DoclensScreen();
    const card = DoclensScreen(
      referenceIdCardChrome: true,
      multiPage: true,
      maxPages: 2,
      autoFinishAtPageLimit: true,
      quickCardCapture: true,
    );
    expect(regular.quickCardCapture, isFalse);
    expect(card.quickCardCapture, isTrue);
  });
}
