import 'dart:convert';

import 'package:doclens/doclens.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ScanSettingsStore {
  static const _key = 'docscanner.scan_preferences.v1';
  static const _cameraChannel = MethodChannel('doclens/methods');
  static Future<void> _pendingWrite = Future<void>.value();

  static Future<ReferenceScanSettings> load() async {
    try {
      // Me and the camera share one settings record. Never read it while
      // a prior toggle's asynchronous write is still waiting to finish.
      await _pendingWrite;
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw != null) {
        final data = jsonDecode(raw);
        if (data is Map<String, dynamic>) {
          return ReferenceScanSettings.fromJson(data);
        }
      }
    } catch (_) {
      // No saved preferences yet, or a previous version wrote invalid data.
    }
    return ReferenceScanSettings();
  }

  static Future<void> save(ReferenceScanSettings settings) {
    // Capture this exact toggle state before awaiting a platform call.
    // Serialising writes prevents older toggles from overwriting a newer
    // value when several switches are tapped in quick succession.
    final snapshot = jsonEncode(settings.toJson());
    _pendingWrite = _pendingWrite.then((_) async {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_key, snapshot);
      } catch (_) {
        // Keep the live settings interactive if device preferences fail.
      }
    });
    return _pendingWrite;
  }

  /// Return only real rear-camera JPEG resolutions, not fabricated presets.
  /// A blank list means the native capability query is not available.
  static Future<List<ScanCameraMode>> availableModes() async {
    try {
      final data = await _cameraChannel.invokeListMethod<dynamic>(
        'getCaptureResolutions',
      );
      if (data == null) return const [];
      final sizes = <ScanCameraMode>[];
      for (final size in data) {
        if (size is List && size.length == 2 &&
            size[0] is num && size[1] is num) {
          sizes.add(ScanCameraMode(
            (size[0] as num).toInt(), (size[1] as num).toInt(),
          ));
        }
      }
      return sizes;
    } on MissingPluginException {
      return const [];
    } on PlatformException {
      return const [];
    }
  }

  static Future<bool> saveImageToGallery(String imagePath) async {
    try {
      return await _cameraChannel.invokeMethod<bool>(
        'saveImageToGallery', {'imagePath': imagePath},
      ) ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
