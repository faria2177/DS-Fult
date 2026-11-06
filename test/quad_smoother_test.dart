import 'package:doclens/doclens.dart';
import 'package:flutter_test/flutter_test.dart';

Quad rectangle(double x, double y, {double width = .42, double height = .55}) {
  return Quad(
    topLeft: Offset(x, y),
    topRight: Offset(x + width, y),
    bottomRight: Offset(x + width, y + height),
    bottomLeft: Offset(x, y + height),
  );
}

void main() {
  test('first detected document immediately gets its four-corner outline', () {
    final tracker = QuadSmoother(windowSize: 7);
    final document = rectangle(.20, .18);
    expect(tracker.add(document), document);
  });

  test('small detector jitter stays on the document', () {
    final tracker = QuadSmoother(windowSize: 7);
    for (var i = 0; i < 9; i++) {
      tracker.add(rectangle(.2 + (i.isEven ? .006 : -.006), .18));
    }
    final result = tracker.add(rectangle(.20, .18))!;
    expect((result.topLeft.dx - .20).abs(), lessThan(.01));
    expect((result.topLeft.dy - .18).abs(), lessThan(.01));
  });

  test('one false background rectangle cannot move the green outline', () {
    final tracker = QuadSmoother(windowSize: 7);
    final original = rectangle(.10, .12);
    final falseDetection = rectangle(.45, .30);
    for (var i = 0; i < 5; i++) {
      tracker.add(original);
    }
    expect(tracker.add(falseDetection), original);
    expect(tracker.add(original), original);
    expect(tracker.add(falseDetection), original);
  });

  test('switches only after three consistent observations of a new page', () {
    final tracker = QuadSmoother(windowSize: 7);
    final oldPage = rectangle(.08, .10);
    final newPage = rectangle(.43, .34);
    tracker.add(oldPage);
    expect(tracker.add(newPage), oldPage);
    expect(tracker.add(rectangle(.434, .343)), oldPage);
    final switched = tracker.add(rectangle(.431, .341))!;
    expect(switched.maxCornerDistance(newPage), lessThan(.01));
    expect(switched.maxCornerDistance(oldPage), greaterThan(.20));
  });

  test('gradual document motion continues to follow camera movement', () {
    final tracker = QuadSmoother(windowSize: 5);
    tracker.add(rectangle(.10, .12));
    Quad? result;
    for (var i = 1; i <= 7; i++) {
      result = tracker.add(rectangle(.10 + i * .025, .12));
    }
    expect(result, isNotNull);
    expect(result!.topLeft.dx, greaterThan(.18));
    expect(result.topLeft.dx, lessThan(.275));
  });

  test('transient misses retain quad, consecutive misses clear it', () {
    final tracker = QuadSmoother(windowSize: 5, missesBeforeReset: 3);
    final doc = rectangle(.2, .2);
    tracker.add(doc);
    expect(tracker.add(null), doc);
    expect(tracker.add(null), doc);
    expect(tracker.add(null), isNull);
    expect(tracker.add(rectangle(.41, .1)), rectangle(.41, .1));
  });

  test('persistent inconsistent frames hide a stale document outline', () {
    final tracker = QuadSmoother(windowSize: 5, maxUnmatchedFrames: 6);
    final original = rectangle(.1, .1);
    tracker.add(original);
    // Alternating distant detections must not confirm either challenger.
    for (var i = 0; i < 5; i++) {
      expect(tracker.add(rectangle(i.isEven ? .55 : .32, .32)), original);
    }
    expect(tracker.add(rectangle(.55, .32)), isNull);
    expect(tracker.add(null), isNull);
    // It can still recover as soon as the original document comes back.
    expect(tracker.add(original), original);
  });
}
