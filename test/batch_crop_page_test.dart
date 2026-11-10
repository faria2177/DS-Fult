import 'package:docscanner/src/screens/batch_crop_screen.dart';
import 'package:docscanner/src/services/image_processor.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Batch crop starts with eight handles and keeps the raw source safe', () {
    final page = BatchCropPageState();
    expect(page.handles, hasLength(8));
    expect(page.confirmed, isFalse);
    expect(page.turns, 0);
    expect(CropQuad(page.corners).isValid, isTrue);
  });

  test('Batch crop edge handle moves both corners and keeps a convex quad', () {
    final page = BatchCropPageState();
    final original = [...page.corners];
    expect(page.updateHandle(4, const Offset(0, .05)), isTrue);
    expect(page.corners[0].dy, closeTo(original[0].dy + .05, .0001));
    expect(page.corners[1].dy, closeTo(original[1].dy + .05, .0001));
    expect(page.corners[2], original[2]);
    expect(page.confirmed, isTrue);
    expect(CropQuad(page.corners).isValid, isTrue);
  });

  test('Dragging a corner beyond the image is rejected without mutation', () {
    final page = BatchCropPageState();
    final original = [...page.corners];
    expect(page.updateHandle(0, const Offset(-2, -2)), isFalse);
    expect(page.corners, original);
    expect(page.confirmed, isFalse);
  });
}
