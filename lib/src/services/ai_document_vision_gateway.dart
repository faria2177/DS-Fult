import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';

import 'ai_credential_store.dart';
import 'ai_provider_catalog.dart';
import 'ai_text_gateway.dart';

enum AiDocumentFormat { word, excel }

abstract class AiDocumentVisionEngine {
  Future<AiTextConfig?> activeConfiguration();
  Future<String> transcribe({required AiTextConfig config,
    required AiDocumentFormat format, required Uint8List jpeg});
}

/// Shrink a user-approved page in memory. The original is never modified.
abstract final class AiPageImage {
  static const maxUploadBytes = 2300000;

  static Future<Uint8List> prepare(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw const AiTextException('Selected page image is missing.');
    }
    if (await file.length() > 25000000) {
      throw const AiTextException('Page image is too large for AI vision.');
    }
    try {
      return await compute(_compressJpeg, await file.readAsBytes());
    } catch (_) {
      throw const AiTextException('Could not prepare this scan for AI vision.');
    }
  }
}

Uint8List _compressJpeg(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) throw const FormatException('Unsupported image');
  var image = img.bakeOrientation(decoded);
  var size = math.max(image.width, image.height);
  if (size > 2200) {
    image = img.copyResize(image,
      width: (image.width * 2200 / size).round(),
      height: (image.height * 2200 / size).round());
  }
  for (final quality in [88, 78, 65]) {
    final jpeg = Uint8List.fromList(img.encodeJpg(image, quality: quality));
    if (jpeg.length <= AiPageImage.maxUploadBytes) return jpeg;
  }
  size = math.max(image.width, image.height);
  if (size > 1500) {
    image = img.copyResize(image,
      width: (image.width * 1500 / size).round(),
      height: (image.height * 1500 / size).round());
  }
  final jpeg = Uint8List.fromList(img.encodeJpg(image, quality: 65));
  if (jpeg.length > AiPageImage.maxUploadBytes) {
    throw const FormatException('Image cannot be compressed safely');
  }
  return jpeg;
}

/// Optional BYOK vision OCR. One image per explicit approval, fixed HTTPS
/// hosts, no document names/paths, no storage, and no automatic background
/// uploads. The user must review/edit the returned OCR before export.
class AiDocumentVisionGateway implements AiDocumentVisionEngine {
  AiDocumentVisionGateway({AiCredentialStore? credentialStore,
    AiTextSender? sender})
      : _vault = credentialStore ?? const SecureAiCredentialStore(),
        _sender = sender ?? AiTextGateway.sendJson;

  final AiCredentialStore _vault;
  final AiTextSender _sender;

  static final _modelPattern = RegExp(r'^[A-Za-z0-9._:/-]{2,110}$');

  @override
  Future<AiTextConfig?> activeConfiguration() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('ai_mode_enabled') != true) return null;
    final id = prefs.getString('ai_mode_active_provider') ?? '';
    final defaultModel = AiProviderCatalog.visionModels[id];
    if (defaultModel == null || !await _vault.hasKey(id)) return null;
    return AiTextConfig(providerId: id,
      providerName: AiProviderCatalog.byId(id)?.name ?? id,
      modelId: prefs.getString('ai_vision_model_$id') ?? defaultModel);
  }

  @override
  Future<String> transcribe({required AiTextConfig config,
    required AiDocumentFormat format, required Uint8List jpeg}) async {
    if (jpeg.isEmpty || jpeg.length > AiPageImage.maxUploadBytes) {
      throw const AiTextException('AI image must be a JPEG under 2.3 MB.');
    }
    final current = await activeConfiguration();
    if (current == null || current.providerId != config.providerId ||
        current.modelId != config.modelId ||
        !_modelPattern.hasMatch(config.modelId)) {
      throw const AiTextException('AI vision settings changed. Try again.');
    }
    final key = await _vault.readKey(config.providerId);
    if (key == null || key.trim().isEmpty) {
      throw const AiTextException('API key missing. Open Me → AI Mode.');
    }

    final guidance = format == AiDocumentFormat.excel
      ? 'Transcribe this scanned document into a precise spreadsheet. '
        'Return plain tab-separated values (TSV): one physical table row '
        'per line, tab between actual table columns. Preserve all rows, '
        'headings, blank cells, dates, names, numbers and Bengali/English '
        'exactly as visible. Do not fabricate cells or totals.'
      : 'Transcribe this scanned page accurately for an editable Word '
        'document. Preserve reading order, section headings, paragraphs, '
        'lists, dates, names, numbers and Bengali/English exactly as seen. '
        'For visible tables, use one tab between columns and one line per '
        'row so the document can recreate editable tables. Keep paragraphs '
        'outside tables on their own lines.';
    final prompt = '$guidance If any detail is illegible, leave it blank '
      'rather than guessing. Output only the transcription: no markdown, '
      'code fences or explanations.';
    final encoded = base64Encode(jpeg);
    late final Uri endpoint;
    late final Map<String, dynamic> body;
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (config.providerId == 'gemini') {
      endpoint = Uri.https('generativelanguage.googleapis.com',
        '/v1beta/models/${config.modelId}:generateContent');
      headers['x-goog-api-key'] = key;
      body = {
        'contents': [{'role': 'user', 'parts': [
          {'text': prompt},
          {'inline_data': {'mime_type': 'image/jpeg', 'data': encoded}},
        ]}],
        'generationConfig': {'temperature': 0, 'maxOutputTokens': 6500},
      };
    } else {
      endpoint = config.providerId == 'groq'
          ? Uri.https('api.groq.com', '/openai/v1/chat/completions')
          : config.providerId == 'openrouter'
              ? Uri.https('openrouter.ai', '/api/v1/chat/completions')
              : throw const AiTextException('Vision provider not supported.');
      headers['Authorization'] = 'Bearer $key';
      body = {
        'model': config.modelId,
        'stream': false,
        'temperature': 0,
        if (config.providerId == 'groq') 'max_completion_tokens': 6500,
        if (config.providerId != 'groq') 'max_tokens': 6500,
        'messages': [{'role': 'user', 'content': [
          {'type': 'text', 'text': prompt},
          {'type': 'image_url', 'image_url': {
            'url': 'data:image/jpeg;base64,$encoded',
          }},
        ]}],
      };
    }

    Map<String, dynamic> result;
    try {
      result = await _sender(endpoint, headers, body);
    } on AiTextException {
      rethrow;
    } catch (_) {
      throw const AiTextException('Vision request failed. Check connection.');
    }
    String response;
    try {
      if (config.providerId == 'gemini') {
        final candidates = result['candidates'] as List;
        final parts = ((candidates.first as Map)['content'] as Map)['parts'] as List;
        response = parts.map((p) => (p as Map)['text'] ?? '')
            .whereType<String>().join();
      } else {
        final choices = result['choices'] as List;
        response = ((choices.first as Map)['message'] as Map)['content'] as String;
      }
    } catch (_) {
      throw const AiTextException('AI returned an unreadable result.');
    }
    response = response.trim();
    if (response.startsWith('```') && response.endsWith('```')) {
      response = response.replaceFirst(RegExp(r'^```[^\n]*\n'), '')
        .replaceFirst(RegExp(r'\n```$'), '').trim();
    }
    if (response.isEmpty || response.length > 30000) {
      throw const AiTextException('AI returned no usable transcription.');
    }
    return response;
  }
}
