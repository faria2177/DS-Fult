import 'package:doclens/doclens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:docscanner/src/screens/id_card_template_screen.dart';
import 'package:docscanner/src/screens/id_card_templates.dart';

void main() {
  test('six reference templates map to the right capture modes', () {
    expect(IdCardTemplate.values.length, 6);
    expect(IdCardTemplate.idCard.sideCount, 2);
    expect(IdCardTemplate.driverLicense.sideCount, 2);
    expect(IdCardTemplate.bankCard.sideCount, 2);
    expect(IdCardTemplate.passport.sideCount, 1);
    expect(IdCardTemplate.certificate.portraitGuide, isTrue);
    expect(IdCardTemplate.general.portraitGuide, isFalse);
    expect(IdCardTemplate.idCard.sideName(1), 'Back');
  });

  testWidgets('ID Cards mode shows reference selector and Make it now', (tester) async {
    IdCardTemplate selected = IdCardTemplate.general;
    var opened = false;
    await tester.pumpWidget(MaterialApp(
      home: StatefulBuilder(builder: (context, repaint) =>
        IdCardTemplateChooserContent(
          selected: selected,
          preview: const ColoredBox(color: Color(0xFF333333)),
          onSelect: (mode) => repaint(() => selected = mode),
          onClose: () {}, onFlash: () {}, onHd: () {},
          onSettings: () {}, onMakeItNow: () => opened = true,
        )),
    ));
    expect(find.text('General'), findsOneWidget);
    expect(find.text('ID Card'), findsOneWidget);
    expect(find.text('Driver License'), findsOneWidget);
    expect(find.text('Passport'), findsOneWidget);
    expect(find.text('Bank Card'), findsOneWidget);
    expect(find.byKey(const Key('id-example-general')), findsOneWidget);
    await tester.tap(find.byKey(const Key('id-template-idCard')));
    await tester.pump();
    expect(find.byKey(const Key('id-example-idCard')), findsOneWidget);
    await tester.tap(find.byKey(const Key('id-make-it-now')));
    expect(opened, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('card capture guides render both aspect ratios', (tester) async {
    for (final portrait in [false, true]) {
      final settings = ReferenceScanSettings();
      await tester.pumpWidget(MaterialApp(home: ReferenceIdCardChrome(
        preview: const ColoredBox(color: Color(0xFF333333)),
        label: portrait ? 'Passport' : 'ID Card',
        side: 'Front',
        portraitGuide: portrait,
        accent: const Color(0xFF00BBA4),
        flashMode: FlashMode.off,
        capturing: false,
        settings: settings,
        onClose: () {}, onFlash: () {}, onCapture: () {},
      )));
      expect(find.byKey(const Key('card-shutter')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      settings.dispose();
    }
  });
}
