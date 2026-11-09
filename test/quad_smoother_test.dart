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

  test('switches only after four consistent observations of a new page', () {
    final tracker = QuadSmoother(windowSize: 7);
    final oldPage = rectangle(.08, .10);
    final newPage = rectangle(.43, .34);
    tracker.add(oldPage);
    expect(tracker.add(newPage), oldPage);
    expect(tracker.add(rectangle(.434, .343)), oldPage);
    expect(tracker.add(rectangle(.431, .341)), oldPage);
    final switched = tracker.add(rectangle(.432, .340))!;
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

  test('rejects crossed corners and impossible geometry', () {
    final tracker = QuadSmoother();
    final doc = rectangle(.2, .2);
    tracker.add(doc);
    final crossed = Quad(
      topLeft: const Offset(.2, .2),
      topRight: const Offset(.6, .7),
      bottomRight: const Offset(.6, .2),
      bottomLeft: const Offset(.2, .7),
    );
    expect(tracker.add(crossed), doc);
    expect(tracker.add(rectangle(.2, .2)), doc);
  });

  test('four drifting challengers cannot steal the outline', () {
    final tracker = QuadSmoother(
      switchConfirmationFrames: 4, maxUnmatchedFrames: 12,
    );
    final doc = rectangle(.15, .15);
    tracker.add(doc);
    for (var i = 0; i < 8; i++) {
      final output = tracker.add(rectangle(
        .45 + (i % 3) * .075, .29, width: .30,
      ));
      expect(output, doc);
    }
  });

  test('small vibration is damped but deliberate movement follows promptly', () {
    final tracker = QuadSmoother(windowSize: 7);
    tracker.add(rectangle(.15, .14));
    for (var i = 0; i < 10; i++) {
      final q = tracker.add(rectangle(.15 + (i.isEven ? .004 : -.004), .14))!;
      expect((q.topLeft.dx - .15).abs(), lessThan(.012));
    }
    Quad? result;
    for (var i = 1; i <= 5; i++) {
      result = tracker.add(rectangle(.15 + i * .030, .14));
    }
    expect(result!.topLeft.dx, greaterThan(.20));
  });

  test('micro-jitter inside display deadband does not shift the border', () {
    final tracker = QuadSmoother(windowSize: 7);
    final document = rectangle(.20, .18);
    tracker.add(document);
    for (var i = 0; i < 12; i++) {
      final result = tracker.add(
          rectangle(.20 + (i.isEven ? .003 : -.003), .18));
      expect(result, document);
    }
  });

  test('full-preview camera border is not a document quadrilateral', () {
    final tracker = QuadSmoother(windowSize: 7);
    expect(tracker.add(rectangle(.001, .001, width: .998, height: .81)),
        isNull);
    final document = rectangle(.23, .18);
    expect(tracker.add(document), document);
  });

  test('sudden near-edge background takeover requires extra confirmation', () {
    final tracker = QuadSmoother(windowSize: 7, maxUnmatchedFrames: 12);
    final cloth = rectangle(.20, .20, width: .35, height: .40);
    final chair = rectangle(.015, .10, width: .65, height: .73);
    tracker.add(cloth);
    for (var i = 0; i < 7; i++) {
      expect(tracker.add(chair), cloth);
    }
    expect(tracker.add(chair), chair);
  });

  test('default tracker never blinks during a coherent delayed challenger', () {
    final tracker = QuadSmoother(windowSize: 7);
    final cloth = rectangle(.20, .20, width: .35, height: .40);
    final nearBorder = rectangle(.015, .10, width: .65, height: .73);
    expect(tracker.add(cloth), cloth);
    // With the default six-frame stale-outline limit and an eight-frame
    // border confirmation, the older implementation hid the green outline
    // for frames 6 and 7 even though the new candidate was consistent.
    for (var i = 0; i < 7; i++) {
      expect(tracker.add(nearBorder), cloth,
          reason: 'Do not blink during delayed takeover frame ${i + 1}');
    }
    final switched = tracker.add(nearBorder);
    expect(switched, isNotNull);
    expect(switched!.maxCornerDistance(nearBorder), lessThan(.005));
  });

  test('null observations interrupt an incompatible contender streak', () {
    final tracker = QuadSmoother(windowSize: 7);
    final cloth = rectangle(.16, .15, width: .30, height: .40);
    tracker.add(cloth);
    for (var i = 0; i < 4; i++) {
      expect(tracker.add(rectangle(.55, .38, width: .35)), cloth);
      expect(tracker.add(rectangle(.32, .38, width: .35)), cloth);
      expect(tracker.add(null), cloth,
          reason: 'One blank camera frame must not compound false switches');
    }
    expect(tracker.add(cloth), cloth);
  });
}
