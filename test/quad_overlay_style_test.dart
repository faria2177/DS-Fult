import 'package:doclens/doclens.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('live filled green quad uses a thicker border', () {
    final filled = quadOverlayFor(
      style: QuadOverlayStyle.filled,
      quad: null,
      status: DetectionStatus.searching,
    );
    expect(filled.strokeWidth, 3.5);

    // Other overlay modes retain their original stroke proportions.
    final outline = quadOverlayFor(
      style: QuadOverlayStyle.outline,
      quad: null,
      status: DetectionStatus.searching,
    );
    expect(outline.strokeWidth, 2.0);
  });
}
