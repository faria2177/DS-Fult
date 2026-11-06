import 'package:doclens/doclens.dart';
import 'package:docscanner/src/services/document_edges.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Scanner tracks a stable four-corner outline with manual capture', () {
    final config = DocumentEdges.scannerConfig;
    expect(config.enableAutoCapture, isFalse);
    expect(config.enableAutoCaptureConfirmation, isFalse);
    expect(config.detectionPolarity, DetectionPolarity.auto);
    expect(config.detectionThresholdOffset, 12);
    expect(config.enableQuadSmoothing, isTrue);
    expect(config.quadSmoothingWindow, 9);
    expect(config.enableSharpnessGate, isTrue);
    expect(config.enablePerspectiveWarp, isTrue);
    expect(config.autoCaptureStabilityDuration.inMilliseconds, 1100);
    expect(config.autoCaptureConfirmationDelay.inMilliseconds, 400);
  });
}
