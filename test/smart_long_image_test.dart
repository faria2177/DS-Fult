import 'package:docscanner/src/models.dart';
import 'package:docscanner/src/services/image_tool_operations.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('doclens/methods');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final document = ScanDocument(
    id: 'd', name: 'Receipt', createdAt: DateTime(2026, 11, 21),
    pages: const [
      ScanPage(id: 'a', path: '/a.jpg', originalPath: '/a.jpg'),
      ScanPage(id: 'b', path: '/b.jpg', originalPath: '/b.jpg'),
    ],
  );

  tearDown(() {
    ImageToolOperations.nativeStitchEnabled = false;
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('uses the native stitcher and reports merged joins', () async {
    ImageToolOperations.nativeStitchEnabled = true;
    MethodCall? seen;
    final jpeg = Uint8List.fromList([1, 2, 3]);
    messenger.setMockMethodCallHandler(channel, (call) async {
      seen = call;
      return {'jpeg': jpeg, 'merged': 1};
    });
    final result = await ImageToolOperations.createSmartLongImage(document,
        watermark: true);
    expect(result.bytes, jpeg);
    expect(result.merged, 1);
    expect(seen?.method, 'stitchLongImage');
    final args = seen?.arguments as Map;
    expect(args['paths'], ['/a.jpg', '/b.jpg']);
    expect(args['watermark'], isTrue);
    expect(args['smart'], isTrue);
  });

  test('a too-tall result surfaces as a readable error', () async {
    ImageToolOperations.nativeStitchEnabled = true;
    messenger.setMockMethodCallHandler(channel, (call) async =>
        throw PlatformException(code: 'too_long', message: 'Too tall'));
    expect(ImageToolOperations.createSmartLongImage(document),
        throwsA(isA<FormatException>()));
  });
}
