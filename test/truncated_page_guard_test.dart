import 'package:doclens/doclens.dart';
import 'package:flutter_test/flutter_test.dart';

Quad box(double left, double top, double right, double bottom) => Quad(
  topLeft: Offset(left, top),
  topRight: Offset(right, top),
  bottomRight: Offset(right, bottom),
  bottomLeft: Offset(left, bottom),
);

void main() {
  // Notebook page as in the field video, and the same page cut short by a
  // ruled line two thirds of the way down (left border kept).
  final page = box(.08, .10, .90, .86);
  final cutByRuledLine = box(.09, .22, .93, .60);
  final idCardOnPage = box(.32, .38, .66, .58);

  group('isTruncatedPage', () {
    test('a page cut short by a ruled line is detected', () {
      expect(isTruncatedPage(cutByRuledLine, page), isTrue);
      expect(isTruncatedPage(box(.08, .10, .90, .55), page), isTrue);
    });

    test('a separate small document on the page is not', () {
      expect(isTruncatedPage(idCardOnPage, page), isFalse);
    });

    test('nearly the same page or a bigger one is not', () {
      expect(isTruncatedPage(box(.09, .11, .89, .85), page), isFalse);
      expect(isTruncatedPage(page, cutByRuledLine), isFalse);
    });
  });

  group('QuadSmoother', () {
    test('keeps the full page while a ruled-line box persists briefly', () {
      final tracker = QuadSmoother(windowSize: 5);
      for (var i = 0; i < 5; i++) {
        tracker.add(page);
      }
      for (var i = 0; i < 20; i++) {
        final shown = tracker.add(cutByRuledLine)!;
        expect(shown.maxCornerDistance(page), lessThan(.01),
            reason: 'frame $i must still show the full page');
      }
    });

    test('a truncated box held for a long time is finally accepted', () {
      final tracker = QuadSmoother(windowSize: 5);
      tracker.add(page);
      Quad? shown;
      for (var i = 0; i < 24; i++) {
        shown = tracker.add(cutByRuledLine);
      }
      expect(shown!.maxCornerDistance(cutByRuledLine), lessThan(.01));
    });

    test('an ID card on the page still switches after four frames', () {
      final tracker = QuadSmoother(windowSize: 5);
      tracker.add(page);
      Quad? shown;
      for (var i = 0; i < 4; i++) {
        shown = tracker.add(idCardOnPage);
      }
      expect(shown!.maxCornerDistance(idCardOnPage), lessThan(.01));
    });
  });

  group('ShutterQuadSelector', () {
    final t0 = DateTime(2026, 11, 18, 20);
    DateTime at(int ms) => t0.add(Duration(milliseconds: ms));

    test('uses the painted box when nothing changed', () {
      final selector = ShutterQuadSelector()..record(page, at(0));
      expect(selector.select(at(2000)), page);
    });

    test('a recent truncated box is cropped as the full page', () {
      final selector = ShutterQuadSelector()
        ..record(page, at(0))
        ..record(cutByRuledLine, at(1200));
      expect(selector.select(at(2000)), page);
    });

    test('a truncated box kept on screen long enough is respected', () {
      final selector = ShutterQuadSelector()
        ..record(page, at(0))
        ..record(cutByRuledLine, at(1000));
      expect(selector.select(at(3000)), cutByRuledLine);
    });

    test('moving to an ID card on the page crops the card', () {
      final selector = ShutterQuadSelector()
        ..record(page, at(0))
        ..record(idCardOnPage, at(1500));
      expect(selector.select(at(1700)), idCardOnPage);
    });

    test('no box on screen means no box', () {
      final selector = ShutterQuadSelector()
        ..record(page, at(0))
        ..record(null, at(500));
      expect(selector.select(at(600)), isNull);
    });
  });
}
