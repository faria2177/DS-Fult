import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:doclens/doclens.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';

import 'ai_credential_store.dart';
import 'image_processor.dart';

/// Online First is opt-in because identity documents contain private data.
/// The endpoint and consent are stored locally; the API secret is held in the
/// OS-backed encrypted vault. No image is sent until all three are configured.
class OnlineAutoCropConfig {
  const OnlineAutoCropConfig({required this.endpoint, required this.consent});
  final String endpoint;
  final bool consent;

  static const endpointKey = 'docscanner.online_crop.endpoint.v1';
  static const consentKey = 'docscanner.online_crop.consent.v1';
  static const secretId = 'docscanner_online_crop_backend';
  static const vault = SecureAiCredentialStore();

  static Uri? safeEndpoint(String input) {
    final uri = Uri.tryParse(input.trim());
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty ||
        uri.userInfo.isNotEmpty || uri.hasQuery || uri.hasFragment ||
        uri.port == 0) {
      return null;
    }
    return uri;
  }

  static Future<OnlineAutoCropConfig> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return OnlineAutoCropConfig(
        endpoint: prefs.getString(endpointKey) ?? '',
        consent: prefs.getBool(consentKey) == true,
      );
    } catch (_) {
      return const OnlineAutoCropConfig(endpoint: '', consent: false);
    }
  }

  bool get ready => consent && safeEndpoint(endpoint) != null;

  static Future<bool> canUpload() async => (await load()).ready;

  static Future<void> save({
    required String endpoint,
    required bool consent,
    String? newSecret,
  }) async {
    final uri = safeEndpoint(endpoint);
    if (consent && uri == null) {
      throw const FormatException('Enter a valid HTTPS AI detector URL.');
    }
    final prefs = await SharedPreferences.getInstance();
    // Revoke immediately before editing any other setting.
    if (!consent) await prefs.setBool(consentKey, false);
    if (newSecret != null && newSecret.trim().isNotEmpty) {
      await vault.saveKey(secretId, newSecret.trim());
    }
    if (consent && !await vault.hasKey(secretId)) {
      throw const FormatException('Enter the detector access token.');
    }
    await prefs.setString(endpointKey, uri?.toString() ?? endpoint.trim());
    if (consent) await prefs.setBool(consentKey, true);
  }

  static Future<void> revoke() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(consentKey, false);
  }
}

class OnlineCropCandidate {
  const OnlineCropCandidate(this.detection, this.confidence, this.documentType);
  final ImageDetection detection;
  final double confidence;
  final String documentType;
}

/// Strict JSON contract: normalized points in TL, TR, BR, BL order. This only
/// proposes a quad; DocumentEdges still applies its independent geometry gates.
class OnlineAutoCropService {
  const OnlineAutoCropService();

  static const maxSourceBytes = 25000000;
  static const maxUploadBytes = 1600000;

  static OnlineCropCandidate? parseResponse(
      Map<String, dynamic> data, Size orientedImageSize) {
    if (data['success'] != true) return null;
    final confidence = data['confidence'];
    final documentType = data['document_type'];
    final pointsData = data['corners'];
    if (confidence is! num || !confidence.isFinite ||
        confidence < .82 || confidence > 1 ||
        (documentType != 'document' && documentType != 'id_card') ||
        pointsData is! Map) {
      return null;
    }
    Offset? point(String key) {
      final v = pointsData[key];
      if (v is! List || v.length != 2 ||
          v[0] is! num || v[1] is! num) {
        return null;
      }
      final x = (v[0] as num).toDouble();
      final y = (v[1] as num).toDouble();
      if (!x.isFinite || !y.isFinite || x < .003 || y < .003 ||
          x > .997 || y > .997) {
        return null;
      }
      return Offset(x, y);
    }
    final tl = point('top_left');
    final tr = point('top_right');
    final br = point('bottom_right');
    final bl = point('bottom_left');
    if (tl == null || tr == null || br == null || bl == null) return null;
    final quad = Quad(topLeft: tl, topRight: tr, bottomRight: br,
      bottomLeft: bl);
    if (!CropQuad(quad.points).isValid ||
        quad.area < .17 || quad.area > .94 ||
        orientedImageSize.width <= 0 || orientedImageSize.height <= 0) {
      return null;
    }
    return OnlineCropCandidate(
      ImageDetection(quad: quad, imageSize: orientedImageSize),
      confidence.toDouble(), documentType as String,
    );
  }

  Future<OnlineCropCandidate?> detect(String imagePath,
      {bool preferIdCardBounds = false}) async {
    final config = await OnlineAutoCropConfig.load();
    if (!config.ready) return null;
    final uri = OnlineAutoCropConfig.safeEndpoint(config.endpoint);
    if (uri == null) return null;
    final token = await OnlineAutoCropConfig.vault.readKey(
        OnlineAutoCropConfig.secretId);
    if (token == null || token.isEmpty) return null;
    final file = File(imagePath);
    if (!await file.exists() || await file.length() > maxSourceBytes) {
      return null;
    }

    final encoded = await compute(_prepareOnlineContourJpeg,
        await file.readAsBytes());
    final jpeg = encoded['jpeg'] as Uint8List;
    final width = encoded['width'] as int;
    final height = encoded['height'] as int;
    if (jpeg.isEmpty || jpeg.length > maxUploadBytes) return null;

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 3)
      ..autoUncompress = false;
    try {
      final request = await client.postUrl(uri)
          .timeout(const Duration(seconds: 4));
      request.followRedirects = false;
      request.headers.set(HttpHeaders.contentTypeHeader, 'image/jpeg');
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set('X-Detector-Key', token);
      request.headers.set('X-Prefer-Card', preferIdCardBounds ? 'true' : 'false');
      request.contentLength = jpeg.length;
      request.add(jpeg);
      final response = await request.close()
          .timeout(const Duration(seconds: 7));
      if (response.statusCode != 200) return null;
      final bytes = <int>[];
      await for (final chunk in response.timeout(const Duration(seconds: 7))) {
        bytes.addAll(chunk);
        if (bytes.length > 32768) return null;
      }
      final json = jsonDecode(utf8.decode(bytes));
      if (json is! Map<String, dynamic>) return null;
      return parseResponse(json, Size(width.toDouble(), height.toDouble()));
    } catch (_) {
      // Timeout, bad TLS, invalid server output or missing internet:
      // the on-device native + Dart detector is always the fallback.
      return null;
    } finally {
      client.close(force: true);
    }
  }
}

/// The image leaves the device only after the user has explicitly enabled
/// online processing. EXIF is baked before downsampling; normalized
/// coordinates are therefore based on the upright original image.
Map<String, Object> _prepareOnlineContourJpeg(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) throw const FormatException('Unsupported image');
  var upright = img.bakeOrientation(decoded);
  final w = upright.width;
  final h = upright.height;
  final longSide = math.max(w, h);
  if (longSide > 1280) {
    upright = img.copyResize(upright,
      width: (w * 1280 / longSide).round(),
      height: (h * 1280 / longSide).round(),
      interpolation: img.Interpolation.linear);
  }
  Uint8List jpeg = Uint8List.fromList(img.encodeJpg(upright, quality: 83));
  if (jpeg.length > OnlineAutoCropService.maxUploadBytes) {
    jpeg = Uint8List.fromList(img.encodeJpg(upright, quality: 65));
  }
  return <String, Object>{'jpeg': jpeg, 'width': w, 'height': h};
}
