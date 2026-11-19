import 'package:docscanner/src/screens/id_card_template_screen.dart';
import 'package:docscanner/src/screens/id_card_templates.dart';
import 'package:doclens/doclens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // The user's phone uses a large system font; it pushed "Make it now" out
  // of its button and crowded the tabs.
  Widget bigFont(Widget child) => MediaQuery(
        data: const MediaQueryData(
          size: Size(400, 860),
          textScaler: TextScaler.linear(1.6),
        ),
        child: MaterialApp(home: child),
      );

  testWidgets('ID Cards chooser keeps its sizes with a large system font',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2322);
    tester.view.devicePixelRatio = 2.7;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(bigFont(IdCardTemplateChooserContent(
      selected: IdCardTemplate.general,
      preview: const ColoredBox(color: Color(0xFF333333)),
      onSelect: (_) {}, onClose: () {}, onFlash: () {}, onHd: () {},
      onSettings: () {}, onMakeItNow: () {},
      flashMode: FlashMode.torch,
    )));
    expect(tester.takeException(), isNull);

    expect(MediaQuery.textScalerOf(tester.element(find.text('Make it now')))
        .scale(10), 10,
        reason: 'system font scaling is clamped to 1.0 on camera screens');
    final button = tester.getRect(find.byKey(const Key('id-make-it-now')));
    final text = tester.getRect(find.text('Make it now'));
    expect(button.top <= text.top && text.bottom <= button.bottom, isTrue,
        reason: 'the label fits inside the button');

    // Flash icon follows the camera's state.
    expect(find.byIcon(Icons.highlight), findsOneWidget);
    // Same tab style as the Scan screen.
    expect(find.byKey(const Key('scan-mode-tab-Scan')), findsOneWidget);
    expect(find.byKey(const Key('scan-mode-tab-ID Cards')), findsOneWidget);
    final scanTab = tester.widget<Text>(find.text('Scan'));
    expect(scanTab.style!.fontSize, ScanChromeStyle.tabFont);
  });

  testWidgets('Scan chrome uses the shared sizes and clamps the font',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2322);
    tester.view.devicePixelRatio = 2.7;
    addTearDown(tester.view.reset);
    final settings = ReferenceScanSettings();
    addTearDown(settings.dispose);
    await tester.pumpWidget(bigFont(Scaffold(body: ReferenceScanChrome(
      preview: const ColoredBox(color: Color(0xFF333333)),
      flashMode: FlashMode.auto,
      batchMode: false,
      pageCount: 0,
      capturing: false,
      accent: const Color(0xFF19BC9C),
      onClose: () {}, onFlash: () {}, onCapture: () {},
      onBatchChanged: (_) {}, onFinishBatch: () {},
      settings: settings,
      onIdCards: () {},
    ))));
    expect(tester.takeException(), isNull);
    expect(tester.widget<Text>(find.text('Single')).style!.fontSize,
        ScanChromeStyle.modeFont);
    expect(tester.widget<Text>(find.text('ID Cards')).style!.fontSize,
        ScanChromeStyle.tabFont);
    expect(tester.widget<Text>(find.text('Import Files')).style!.fontSize,
        ScanChromeStyle.actionFont);
    expect(MediaQuery.textScalerOf(tester.element(find.text('Single')))
        .scale(10), 10);
  });
}
