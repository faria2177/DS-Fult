import 'package:docscanner/src/services/online_auto_crop_service.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> response({
  String type = 'document',
  double confidence = .96,
  List<double> tl = const [.08, .08],
  List<double> tr = const [.92, .08],
  List<double> br = const [.92, .92],
  List<double> bl = const [.08, .92],
}) => <String, dynamic>{
  'success': true,
  'document_type': type,
  'confidence': confidence,
  'corners': <String, dynamic>{
    'top_left': tl,
    'top_right': tr,
    'bottom_right': br,
    'bottom_left': bl,
  },
};

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('Online upload starts disabled and requires explicit consent', () async {
    expect((await OnlineAutoCropConfig.load()).consent, isFalse);
    expect(await OnlineAutoCropConfig.canUpload(), isFalse);
  });

  test('HTTPS endpoint validation blocks cleartext and credential leaks', () {
    expect(OnlineAutoCropConfig.safeEndpoint(
        'https://scanner.example/v1/detect'), isNotNull);
    expect(OnlineAutoCropConfig.safeEndpoint(
        'http://scanner.example/v1/detect'), isNull);
    expect(OnlineAutoCropConfig.safeEndpoint(
        'https://token@scanner.example/v1/detect'), isNull);
    expect(OnlineAutoCropConfig.safeEndpoint(
        'https://scanner.example/v1/detect?key=x'), isNull);
    expect(OnlineAutoCropConfig.safeEndpoint('invalid'), isNull);
  });

  test('Valid normalized four corners are parsed as image detection', () {
    final found = OnlineAutoCropService.parseResponse(
      response(), const Size(1200, 900));
    expect(found, isNotNull);
    expect(found!.documentType, 'document');
    expect(found.confidence, .96);
    expect(found.detection.quad?.area, closeTo(.7056, .0001));
  });

  test('Rejects crossed corners, out of bounds and fabricated confidence', () {
    const size = Size(1200, 900);
    expect(OnlineAutoCropService.parseResponse(
      response(tr: [.92, .92], br: [.92, .08]), size), isNull);
    expect(OnlineAutoCropService.parseResponse(
      response(tl: [-.1, .08]), size), isNull);
    expect(OnlineAutoCropService.parseResponse(
      response(confidence: .5), size), isNull);
    expect(OnlineAutoCropService.parseResponse({
      ...response(), 'success': false,
    }, size), isNull);
  });
}
