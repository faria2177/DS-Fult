import 'package:docscanner/src/services/image_processor.dart';
import 'package:docscanner/src/services/native_scanner_core.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('doclens/methods');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  Uint8List grayPage() {
    final page = img.Image(width: 64, height: 80);
    img.fill(page, color: img.ColorRgb8(180, 184, 188));
    return Uint8List.fromList(img.encodePng(page));
  }

  tearDown(() {
    NativeScannerCore.enabled = false;
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('document Enhance uses libds_scannercore when it answers', () async {
    NativeScannerCore.enabled = true;
    final nativeResult = Uint8List.fromList([9, 9, 9]);
    MethodCall? seen;
    messenger.setMockMethodCallHandler(channel, (call) async {
      seen = call;
      return nativeResult;
    });
    final out = await ImageProcessor.process(grayPage(),
        filter: ScanFilter.enhance, documentMode: true);
    expect(out, nativeResult);
    expect(seen?.method, 'nativeMagicEnhance');
    expect((seen?.arguments as Map)['onlyNeutral'], isTrue);
  });

  test('falls back to the Dart Enhance when native returns null', () async {
    NativeScannerCore.enabled = true;
    messenger.setMockMethodCallHandler(channel, (call) async => null);
    final out = img.decodeImage(await ImageProcessor.process(grayPage(),
        filter: ScanFilter.enhance, documentMode: true))!;
    expect(out.getPixel(30, 40).r, greaterThan(240));
  });

  test('native is not used outside document Enhance', () async {
    NativeScannerCore.enabled = true;
    var calls = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls++;
      return null;
    });
    await ImageProcessor.process(grayPage(), filter: ScanFilter.grayscale);
    expect(calls, 0);
  });
}
