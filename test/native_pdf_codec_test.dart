import 'dart:convert';

import 'package:docscanner/src/services/native_pdf_codec.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('doclens/methods');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    NativePdfCodec.enabled = false;
    messenger.setMockMethodCallHandler(channel, null);
  });

  // 64×2 white page, verified byte-for-byte against libtiff's encoder.
  final g4 = Uint8List.fromList([0xc0, 0x04, 0x00, 0x40]);

  test('G4 page is embedded as a 1-bit CCITT image', () async {
    final pdf = pw.Document(compress: false);
    final image = NativePdfCodec.pdfImage(
        pdf.document, BilevelPage(64, 2, g4));
    pdf.addPage(pw.Page(build: (_) => pw.Image(pw.ImageProxy(image))));
    final text = latin1.decode(await pdf.save());
    expect(text, contains('/CCITTFaxDecode'));
    expect(text, contains('/K -1'));
    expect(text, contains('/Columns 64'));
    expect(text, contains('/BitsPerComponent 1'));
    expect(text, contains('/DeviceGray'));
    expect(text, isNot(contains('/DCTDecode')));
  });

  test('bridge passes the page and reads the G4 answer', () async {
    NativePdfCodec.enabled = true;
    MethodCall? seen;
    messenger.setMockMethodCallHandler(channel, (call) async {
      seen = call;
      return {'width': 64, 'height': 2, 'data': g4};
    });
    final page = await NativePdfCodec.bilevelPage('/x/page.jpg', minShare: .95);
    expect(seen?.method, 'pdfBilevelPage');
    expect((seen?.arguments as Map)['minShare'], .95);
    expect(page?.width, 64);
    expect(page?.data, g4);
  });

  test('null when native says the page is not black-and-white', () async {
    NativePdfCodec.enabled = true;
    messenger.setMockMethodCallHandler(channel, (call) async => null);
    expect(await NativePdfCodec.bilevelPage('/x/photo.jpg'), isNull);
  });
}
