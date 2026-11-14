import 'package:doclens/doclens.dart';
import 'package:docscanner/src/services/document_edges.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

ImageDetection page(double left, double top, double right, double bottom,
    {Size size = const Size(1200, 900)}) =>
    ImageDetection(
      quad: Quad(
        topLeft: Offset(left, top),
        topRight: Offset(right, top),
        bottomRight: Offset(right, bottom),
        bottomLeft: Offset(left, bottom),
      ),
      imageSize: size,
    );

void main() {
  test('small, plausible outward pixel-edge adjustment is allowed', () {
    final original = page(.12, .10, .88, .90);
    final refined = page(.11, .09, .89, .91);
    expect(DocumentEdges.isSafeRefinement(original, refined), isTrue);
  });

  test('snapping a page to a smaller printed inset is rejected', () {
    final original = page(.12, .10, .88, .90);
    final titleBox = page(.22, .19, .78, .81);
    expect(DocumentEdges.isSafeRefinement(original, titleBox), isFalse);
  });

  test('a corner jump is rejected even with similar area', () {
    final original = page(.12, .10, .88, .90);
    final offsetPage = page(.02, .10, .78, .90);
    expect(DocumentEdges.isSafeRefinement(original, offsetPage), isFalse);
  });

  test('refined corners outside the capture are never accepted', () {
    final original = page(.12, .10, .88, .90);
    final outside = page(-.01, .10, .89, .90);
    expect(DocumentEdges.isSafeRefinement(original, outside), isFalse);
  });

  test('refinement cannot change the source dimensions', () {
    final original = page(.12, .10, .88, .90);
    final mismatched = page(.11, .09, .89, .91,
        size: const Size(1600, 900));
    expect(DocumentEdges.isSafeRefinement(original, mismatched), isFalse);
  });

  test('valid minor adjustment to a complete ID card is allowed', () {
    final original = page(.22, .27, .78, .67);
    final adjusted = page(.21, .26, .79, .68);
    expect(DocumentEdges.isSafeRefinement(original, adjusted,
        preferIdCardBounds: true), isTrue);
  });

  test('ID card cannot be refined into its interior text block', () {
    final original = page(.22, .27, .78, .67);
    final smaller = page(.29, .30, .71, .64);
    expect(DocumentEdges.isSafeRefinement(original, smaller,
        preferIdCardBounds: true), isFalse);
  });
}
