import 'package:doclens/doclens.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('doclens/methods');

  test('camera capture forwards displayed four green corners, not a new quad',
      () async {
    const visibleGreen = Quad(
      topLeft: Offset(.125, .105),
      topRight: Offset(.89, .12),
      bottomRight: Offset(.88, .905),
      bottomLeft: Offset(.11, .89),
    );
    Map<dynamic, dynamic>? sent;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'capture');
      sent = call.arguments as Map<dynamic, dynamic>?;
      return {
        'croppedImagePath': 'from_green_outline.jpg',
        'rawImagePath': 'raw.jpg',
        'quad': visibleGreen.scaleToSize(const Size(1200, 900)).toMap(),
        'rawImageSize': [1200, 900],
        'liveOutlineAtShutter': true,
        'liveOutlineMatched': true,
      };
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final result =
        await MethodChannelDoclens().captureWithDisplayedQuad(visibleGreen);
    expect(sent, isNotNull);
    expect(sent!['displayedQuad'], visibleGreen.toMap());
    expect(result.liveOutlineAtShutter, isTrue);
    expect(result.liveOutlineMatched, isTrue);
    expect(result.croppedImagePath, 'from_green_outline.jpg');
  });

  test('legacy capture still works with no visible green quad', () async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    dynamic arguments;
    messenger.setMockMethodCallHandler(channel, (call) async {
      arguments = call.arguments;
      return {
        'croppedImagePath': null,
        'rawImagePath': 'raw.jpg',
        'quad': const Quad(
          topLeft: Offset.zero,
          topRight: Offset(1200, 0),
          bottomRight: Offset(1200, 900),
          bottomLeft: Offset(0, 900),
        ).toMap(),
        'rawImageSize': [1200, 900],
      };
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final result = await MethodChannelDoclens().capture();
    expect(arguments, isNull);
    expect(result.liveOutlineAtShutter, isFalse);
    expect(result.liveOutlineMatched, isFalse);
  });
}
