import 'package:doclens/doclens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses native code events', () {
    final codes = LiveCode.listFrom([
      {
        'format': 'QRCode',
        'text': 'https://example.com',
        'corners': [.1, .1, .3, .1, .3, .3, .1, .3],
      },
      {'format': 'EAN-13', 'text': '5901234123457'},
      {'format': 'QRCode', 'text': ''},
      'junk',
    ]);
    expect(codes, hasLength(2));
    expect(codes.first.label, 'QR');
    expect(codes.first.isLink, isTrue);
    expect(codes.first.corners, hasLength(4));
    expect(codes.last.label, 'EAN-13');
    expect(codes.last.isLink, isFalse);
  });

  test('a codes event is info only and does not clear the page', () {
    const event = DetectionEvent(codes: [LiveCode(format: 'QRCode', text: 'x')]);
    expect(event.isInfoOnly, isTrue);
  });

  testWidgets('chip shows the code and calls the app action', (tester) async {
    LiveCode? tapped;
    DoclensCodeActions.onTap = (_, code) => tapped = code;
    addTearDown(() => DoclensCodeActions.onTap = null);
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Center(
        child: LiveCodeChip(codes: [
          LiveCode(format: 'QRCode', text: 'https://example.com'),
        ])))));
    expect(find.text('QR: https://example.com'), findsOneWidget);
    await tester.tap(find.byKey(const Key('doclens-live-code-chip')));
    expect(tapped?.text, 'https://example.com');
  });
}
