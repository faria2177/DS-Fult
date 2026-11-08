import 'dart:async';

import 'package:doclens/doclens.dart';
import 'package:flutter_test/flutter_test.dart';

Quad _rectangle(double x, double y) => Quad(
      topLeft: Offset(x, y),
      topRight: Offset(x + .30, y),
      bottomRight: Offset(x + .30, y + .40),
      bottomLeft: Offset(x, y + .40),
    );

class _LiveFakePlatform extends DoclensPlatform {
  final events = StreamController<DetectionEvent>.broadcast();

  @override
  Future<int> initialize(ScannerConfig config) async => 1;

  @override
  Future<void> dispose() async {}

  @override
  Stream<DetectionEvent> detectionEvents() => events.stream;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('controller never restores a candidate rejected by smoothing', () async {
    final previous = DoclensPlatform.instance;
    final fake = _LiveFakePlatform();
    DoclensPlatform.instance = fake;
    final controller = DoclensController(
      config: const ScannerConfig(enableAutoCapture: false),
    );
    Future<void> emit(Quad quad) async {
      fake.events.add(DetectionEvent(quad: quad));
      await Future<void>.delayed(Duration.zero);
    }

    try {
      await controller.initialize();
      final cloth = _rectangle(.14, .16);
      await emit(cloth);
      expect(controller.lastQuad, cloth);

      // Neither of these alternating detections confirms a new document.
      // At six incompatible frames QuadSmoother deliberately hides the box.
      for (var i = 0; i < 6; i++) {
        await emit(_rectangle(i.isEven ? .55 : .36, .40));
      }
      expect(controller.lastQuad, isNull);
      await emit(cloth);
      expect(controller.lastQuad, cloth);
    } finally {
      await controller.dispose();
      await fake.events.close();
      DoclensPlatform.instance = previous;
    }
  });
}
