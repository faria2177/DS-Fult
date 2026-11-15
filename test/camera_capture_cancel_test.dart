import 'dart:typed_data';

import 'package:docscanner/src/services/camera_crop_review_decision.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('camera Adjust Corners Cancel must discard the pending scan', () {
    expect(cameraCropReviewDecision(null),
        CameraCropReviewDecision.discard);
  });

  test('system Back has identical cancel semantics', () {
    Map<int, Uint8List>? dismissedByBack;
    expect(cameraCropReviewDecision(dismissedByBack),
        CameraCropReviewDecision.discard);
  });

  test('Done with no manual crop explicitly accepts the original', () {
    expect(cameraCropReviewDecision(<int, Uint8List>{}),
        CameraCropReviewDecision.accept);
  });

  test('Done with modified corner image explicitly accepts the crop', () {
    expect(cameraCropReviewDecision(<int, Uint8List>{
      0: Uint8List.fromList([1, 2, 3]),
    }), CameraCropReviewDecision.accept);
  });
}
