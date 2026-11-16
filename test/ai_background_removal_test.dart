import 'dart:typed_data';

import 'package:docscanner/src/services/ai_background_removal.dart';
import 'package:docscanner/src/services/photo_studio_operations.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('doclens/methods');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  test('AI cutout sends normalized photo on-device with chosen background',
      () async {
    final original = img.Image(width: 1920, height: 1080);
    img.fill(original, color: img.ColorRgb8(230, 212, 206));
    final bytes = Uint8List.fromList(img.encodeJpg(original, quality: 85));
    final mockPng = Uint8List.fromList([137, 80, 78, 71]);
    Map<dynamic, dynamic>? sent;
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'removeSubjectBackground');
      sent = call.arguments as Map<dynamic, dynamic>;
      return mockPng;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final result = await AiBackgroundRemoval.remove(
      bytes, backgroundArgb: 0xFFFFFFFF,
    );
    expect(result, mockPng);
    expect(sent?['backgroundArgb'], 0xFFFFFFFF);
    final normalized = sent?['imageBytes'] as Uint8List;
    final dims = PhotoStudioOperations.dimensions(normalized);
    expect(dims[0], 1600);
    expect(dims[1], 900);
  });

  test('unavailable AI model surfaces error instead of silently applying flood-fill',
      () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(
        code: 'ai_model_unavailable',
        message: 'Google Play services model still downloading',
      );
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final original = img.Image(width: 300, height: 300);
    final bytes = Uint8List.fromList(img.encodePng(original));
    await expectLater(
      AiBackgroundRemoval.remove(bytes),
      throwsA(isA<PlatformException>()),
    );
  });
}
