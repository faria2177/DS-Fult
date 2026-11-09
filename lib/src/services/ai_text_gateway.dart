import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

import 'ai_credential_store.dart';
import 'ai_provider_catalog.dart';

enum AiTextTask { proofread, tableCleanup }

class AiTextConfig {
  const AiTextConfig({required this.providerId, required this.providerName,
    required this.modelId});

  final String providerId;
  final String providerName;
  final String modelId;
}

class AiTextException implements Exception {
  const AiTextException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Can be faked in tests; never logs a request, response, credential or text.
typedef AiTextSender = Future<Map<String, dynamic>> Function(
    Uri endpoint, Map<String, String> headers, Map<String, dynamic> body);

abstract class AiTextEngine {
  Future<AiTextConfig?> activeConfiguration();
  Future<String> rewrite({required AiTextConfig config,
    required AiTextTask task, required String text});
}

/// Explicit, text-only BYOK inference; images and document file paths are not
/// accepted by this API. Calls never run during app startup or OCR itself.
class AiTextGateway implements AiTextEngine {
  AiTextGateway({AiCredentialStore? credentialStore, AiTextSender? sender})
      : _vault = credentialStore ?? const SecureAiCredentialStore(),
        _sender = sender ?? sendJson;

  final AiCredentialStore _vault;
  final AiTextSender _sender;

  static const maxInputCharacters = 12000;
  static final _modelIdPattern = RegExp(r'^[A-Za-z0-9._:/-]{2,110}$');

  @override
  Future<AiTextConfig?> activeConfiguration() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('ai_mode_enabled') != true) return null;
    final id = prefs.getString('ai_mode_active_provider') ?? '';
    final model = AiProviderCatalog.textModels[id];
    if (model == null || !await _vault.hasKey(id)) return null;
    final provider = AiProviderCatalog.byId(id);
    return AiTextConfig(providerId: id,
      providerName: provider?.name ?? id,
      modelId: prefs.getString('ai_model_$id') ?? model);
  }

  @override
  Future<String> rewrite({required AiTextConfig config,
      required AiTextTask task, required String text}) async {
    final input = text.trim();
    if (input.isEmpty || input.length > maxInputCharacters) {
      throw const AiTextException('Text must contain 1–12,000 characters.');
    }
    // Check again at send-time so disabled/removed keys cannot be reused from
    // an old approval dialog. A changed active provider requires re-consent.
    final current = await activeConfiguration();
    if (current == null || current.providerId != config.providerId ||
        current.modelId != config.modelId) {
      throw const AiTextException('AI settings changed. Review and try again.');
    }
    if (!_modelIdPattern.hasMatch(config.modelId)) {
      throw const AiTextException('Invalid model ID. Check AI Mode settings.');
    }
    final key = await _vault.readKey(config.providerId);
    if (key == null || key.trim().isEmpty) {
      throw const AiTextException('API key is missing. Add it in Me → AI Mode.');
    }

    final instruction = task == AiTextTask.tableCleanup
        ? 'Correct obvious OCR mistakes in this spreadsheet text. Preserve '
          'every row, newline, tab-separated column and numeric value unless '
          'the original is clearly a recognition error. Do not add a table '
          'heading, markdown, code fences, or commentary. Return only corrected '
          'TSV-like plain text.'
        : 'Proofread OCR text, correcting obvious transcription, spacing, '
          'spelling and punctuation errors. Preserve names, facts, language, '
          'numbers, paragraphs and meaning. Do not invent missing content. '
          'Return corrected plain text only, without markdown or commentary.';

    late final Uri endpoint;
    late final Map<String, dynamic> body;
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (config.providerId == 'gemini') {
      endpoint = Uri.https('generativelanguage.googleapis.com',
        '/v1beta/models/${config.modelId}:generateContent');
      headers['x-goog-api-key'] = key;
      body = {
        'contents': [{'role': 'user', 'parts': [
          {'text': '$instruction\n\nOCR text:\n$input'},
        ]}],
        'generationConfig': {'temperature': 0.1, 'maxOutputTokens': 3000},
      };
    } else {
      endpoint = config.providerId == 'groq'
          ? Uri.https('api.groq.com', '/openai/v1/chat/completions')
          : config.providerId == 'openrouter'
              ? Uri.https('openrouter.ai', '/api/v1/chat/completions')
              : throw const AiTextException('This provider is not supported yet.');
      headers['Authorization'] = 'Bearer $key';
      body = {
        'model': config.modelId,
        'stream': false,
        'max_tokens': 3000,
        'temperature': 0.1,
        'messages': [
          {'role': 'system', 'content': instruction},
          {'role': 'user', 'content': input},
        ],
      };
    }

    Map<String, dynamic> result;
    try {
      result = await _sender(endpoint, headers, body);
    } on AiTextException {
      rethrow;
    } catch (_) {
      throw const AiTextException('AI request failed. Check connection and try again.');
    }

    final String output;
    try {
      if (config.providerId == 'gemini') {
        final candidates = result['candidates'] as List;
        final content = (candidates.first as Map)['content'] as Map;
        final parts = content['parts'] as List;
        output = parts.map((p) => (p as Map)['text'] ?? '')
            .whereType<String>().join();
      } else {
        final choices = result['choices'] as List;
        final message = (choices.first as Map)['message'] as Map;
        output = message['content'] as String;
      }
    } catch (_) {
      throw const AiTextException('AI returned an unsupported response format.');
    }
    if (output.trim().isEmpty) {
      throw const AiTextException('AI returned no text. Nothing was changed.');
    }
    if (output.length > maxInputCharacters * 2) {
      throw const AiTextException('AI response is unexpectedly long.');
    }
    return output.trim();
  }

  /// Shared restricted HTTPS transport for text and opt-in image requests.
  static Future<Map<String, dynamic>> sendJson(Uri endpoint,
      Map<String, String> headers, Map<String, dynamic> body) async {
    // Endpoint hosts are fixed in code. Never send credentials to arbitrary
    // model IDs, redirects or a third-party test URL.
    const permitted = {
      'generativelanguage.googleapis.com', 'api.groq.com', 'openrouter.ai',
    };
    if (endpoint.scheme != 'https' || !permitted.contains(endpoint.host)) {
      throw const AiTextException('Untrusted AI endpoint.');
    }
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15)
      ..idleTimeout = const Duration(seconds: 5);
    try {
      final request = await client.postUrl(endpoint)
          .timeout(const Duration(seconds: 20));
      request.followRedirects = false;
      headers.forEach(request.headers.set);
      request.write(jsonEncode(body));
      final response = await request.close().timeout(const Duration(seconds: 70));
      if (response.statusCode != 200) {
        // Never echo the remote response: it could include private text or key.
        if (response.statusCode == 401 || response.statusCode == 403) {
          throw const AiTextException('API key rejected or access denied.');
        }
        if (response.statusCode == 402) {
          throw const AiTextException('Provider requires billing or credits.');
        }
        if (response.statusCode == 429) {
          throw const AiTextException('Provider rate limit reached. Try later.');
        }
        throw AiTextException('Provider returned HTTP ${response.statusCode}.');
      }
      final bytes = await response.fold<BytesBuilder>(BytesBuilder(copy: false),
          (buffer, chunk) {
        if (buffer.length + chunk.length > 1024 * 1024) {
          throw const AiTextException('AI response is too large.');
        }
        buffer.add(chunk);
        return buffer;
      }).timeout(const Duration(seconds: 70));
      final decoded = jsonDecode(utf8.decode(bytes.takeBytes()));
      if (decoded is! Map<String, dynamic>) {
        throw const AiTextException('Provider returned an invalid response.');
      }
      return decoded;
    } on AiTextException {
      rethrow;
    } on TimeoutException {
      throw const AiTextException('AI request timed out. No text was changed.');
    } on SocketException {
      throw const AiTextException('No connection to the AI provider.');
    } on HandshakeException {
      throw const AiTextException('Secure connection to provider failed.');
    } on FormatException {
      throw const AiTextException('Provider returned invalid JSON.');
    } finally {
      client.close(force: true);
    }
  }
}
