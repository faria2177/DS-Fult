import 'package:doclens/doclens.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('scanner menu defaults match the captured reference video', () {
    final settings = ReferenceScanSettings();
    addTearDown(settings.dispose);
    expect(settings.effect, ScanEffectPreset.enhance);
    expect(settings.autoCapture, isFalse);
    expect(settings.autoCrop, isTrue);
    expect(settings.sound, isTrue);
    expect(settings.grid, isFalse);
    expect(settings.orientation, ScanOrientationMode.auto);
    expect(settings.autoAdjustBorders, isTrue);
    expect(settings.adjustAfterEachScan, isFalse);
  });

  test('changes survive JSON save and restore', () {
    final settings = ReferenceScanSettings()
      ..selectEffect(ScanEffectPreset.magicPro)
      ..selectResolution('4032x3024')
      ..selectOrientation(ScanOrientationMode.landscape)
      ..setFlag('autoCapture', true)
      ..setFlag('doubleFocus', true)
      ..setFlag('saveScansToGallery', true);
    addTearDown(settings.dispose);
    final restored = ReferenceScanSettings.fromJson(settings.toJson());
    addTearDown(restored.dispose);
    expect(restored.effect, ScanEffectPreset.magicPro);
    expect(restored.resolution, '4032x3024');
    expect(restored.orientation, ScanOrientationMode.landscape);
    expect(restored.autoCapture, isTrue);
    expect(restored.doubleFocus, isTrue);
    expect(restored.saveScansToGallery, isTrue);
    expect(restored.panel, ScanCameraPanel.none);
  });
}
