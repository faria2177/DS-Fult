import 'package:flutter/foundation.dart';

enum ScanEffectPreset {
  original('Original'),
  lighten('Lighten'),
  enhance('Enhance'),
  magicPro('Magic Pro'),
  noWatermark('No Watermark'),
  noShadow('No Shadow'),
  noHandwriting('No Handwriting'),
  blackWhite('B&W'),
  eco('Eco'),
  grayscale('Grayscale'),
  invert('Invert');

  const ScanEffectPreset(this.label);
  final String label;
}

enum ScanOrientationMode { auto, portrait, landscape }

enum ScanCameraPanel { none, effects, hd, settings }

class ScanCameraMode {
  const ScanCameraMode(this.width, this.height);
  final int width;
  final int height;

  String get id => '${width}x$height';
  String get label => '${(width * height / 1000000).round()}M ($id)';
}

/// Persisted preferences live in the host application. The plugin only owns
/// the scanner UI, so these values can be shared across new CameraX sessions.
class ReferenceScanSettings extends ChangeNotifier {
  ScanEffectPreset effect = ScanEffectPreset.enhance;
  String resolution = 'auto';
  ScanOrientationMode orientation = ScanOrientationMode.auto;
  bool autoCapture = false;
  bool grid = false;
  bool sound = true;
  bool spiritLevel = false;
  bool autoCrop = true;
  bool autoAdjustBorders = true;
  bool adjustAfterEachScan = false;
  bool startWithCamera = false;
  bool useSystemCamera = false;
  bool importFromGallery = false;
  bool saveScansToGallery = false;
  bool doubleFocus = false;
  ScanCameraPanel panel = ScanCameraPanel.none;
  bool allHdModes = false;

  ReferenceScanSettings();

  factory ReferenceScanSettings.fromJson(Map<String, dynamic> json) {
    final s = ReferenceScanSettings();
    s.effect = ScanEffectPreset.values.firstWhere(
      (value) => value.name == json['effect'],
      orElse: () => ScanEffectPreset.enhance,
    );
    s.resolution = (json['resolution'] as String?) ?? 'auto';
    s.orientation = ScanOrientationMode.values.firstWhere(
      (value) => value.name == json['orientation'],
      orElse: () => ScanOrientationMode.auto,
    );
    for (final key in _keys) {
      if (json[key] is bool) s.setFlag(key, json[key] as bool, notify: false);
    }
    return s;
  }

  static const _keys = [
    'autoCapture', 'grid', 'sound', 'spiritLevel', 'autoCrop',
    'autoAdjustBorders', 'adjustAfterEachScan', 'startWithCamera',
    'useSystemCamera', 'importFromGallery', 'saveScansToGallery', 'doubleFocus',
  ];

  Map<String, dynamic> toJson() => {
        'effect': effect.name,
        'resolution': resolution,
        'orientation': orientation.name,
        for (final key in _keys) key: flag(key),
      };

  bool flag(String key) => switch (key) {
        'autoCapture' => autoCapture,
        'grid' => grid,
        'sound' => sound,
        'spiritLevel' => spiritLevel,
        'autoCrop' => autoCrop,
        'autoAdjustBorders' => autoAdjustBorders,
        'adjustAfterEachScan' => adjustAfterEachScan,
        'startWithCamera' => startWithCamera,
        'useSystemCamera' => useSystemCamera,
        'importFromGallery' => importFromGallery,
        'saveScansToGallery' => saveScansToGallery,
        'doubleFocus' => doubleFocus,
        _ => false,
      };

  void setFlag(String key, bool value, {bool notify = true}) {
    switch (key) {
      case 'autoCapture': autoCapture = value;
      case 'grid': grid = value;
      case 'sound': sound = value;
      case 'spiritLevel': spiritLevel = value;
      case 'autoCrop': autoCrop = value;
      case 'autoAdjustBorders': autoAdjustBorders = value;
      case 'adjustAfterEachScan': adjustAfterEachScan = value;
      case 'startWithCamera': startWithCamera = value;
      case 'useSystemCamera': useSystemCamera = value;
      case 'importFromGallery': importFromGallery = value;
      case 'saveScansToGallery': saveScansToGallery = value;
      case 'doubleFocus': doubleFocus = value;
      default: return;
    }
    if (notify) notifyListeners();
  }

  void selectEffect(ScanEffectPreset value) {
    effect = value;
    notifyListeners();
  }

  void selectResolution(String value) {
    resolution = value;
    notifyListeners();
  }

  void selectOrientation(ScanOrientationMode value) {
    orientation = value;
    notifyListeners();
  }

  void togglePanel(ScanCameraPanel next) {
    panel = panel == next ? ScanCameraPanel.none : next;
    allHdModes = false;
    notifyListeners();
  }

  void closePanel() {
    panel = ScanCameraPanel.none;
    notifyListeners();
  }

  void expandHd(bool expanded) {
    allHdModes = expanded;
    notifyListeners();
  }
}
