import 'dart:typed_data';

import 'package:docscanner/src/services/ai_credential_store.dart';
import 'package:docscanner/src/services/ai_document_vision_gateway.dart';
import 'package:docscanner/src/services/ai_text_gateway.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _KeyVault implements AiCredentialStore {
  final Map<String, String> secrets = {};
  @override
  Future<bool> hasKey(String id) async => secrets.containsKey(id);
  @override
  Future<String?> readKey(String id) async => secrets[id];
  @override
  Future<bool> hasAccountId(String id) async => false;
  @override
  Future<void> saveKey(String id, String key, {String? accountId}) async {
    secrets[id] = key;
  }
  @override
  Future<void> deleteKey(String id) async { secrets.remove(id); }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('AI vision is inactive until enabled with a stored key', () async {
    var calls = 0;
    final gateway = AiDocumentVisionGateway(
      credentialStore: _KeyVault(),
      sender: (_, _, _) async { calls++; return {}; },
    );
    expect(await gateway.activeConfiguration(), isNull);
    expect(calls, 0);
  });

  for (final provider in ['gemini', 'groq', 'openrouter']) {
    test('$provider sends a single in-memory image to its fixed API', () async {
      SharedPreferences.setMockInitialValues({
        'ai_mode_enabled': true,
        'ai_mode_active_provider': provider,
      });
      final vault = _KeyVault()..secrets[provider] = 'test-secret';
      Uri? endpoint;
      Map<String, dynamic>? requestBody;
      var count = 0;
      final gateway = AiDocumentVisionGateway(credentialStore: vault,
        sender: (url, headers, body) async {
          count++;
          endpoint = url;
          requestBody = body;
          expect(headers.toString(), contains('test-secret'));
          return provider == 'gemini'
              ? {'candidates': [{'content': {'parts': [
                  {'text': 'Name\tScore\nDhaka\t4'}
                ]}}]}
              : {'choices': [{'message': {'content': 'Name\tScore\nDhaka\t4'}}]};
        });
      final config = await gateway.activeConfiguration();
      expect(config, isNotNull);
      expect(count, 0, reason: 'Selecting a provider must not upload an image');
      expect(await gateway.transcribe(config: config!,
        format: AiDocumentFormat.excel,
        jpeg: Uint8List.fromList([0xff, 0xd8, 0xff])),
        'Name\tScore\nDhaka\t4');
      expect(count, 1);
      expect(endpoint!.scheme, 'https');
      expect(endpoint!.host, provider == 'gemini'
          ? 'generativelanguage.googleapis.com'
          : provider == 'groq' ? 'api.groq.com' : 'openrouter.ai');
      expect(requestBody.toString(), contains('/9j/'));
      expect(requestBody.toString(), isNot(contains('test-secret')));
      expect(requestBody.toString(), isNot(contains('/storage/emulated')));
      expect(config.modelId, isNot('llama-3.3-70b-versatile'));
    });
  }

  test('a disabled or changed provider cannot send a stale image', () async {
    SharedPreferences.setMockInitialValues({
      'ai_mode_enabled': true, 'ai_mode_active_provider': 'gemini',
    });
    final vault = _KeyVault()..secrets['gemini'] = 'secret';
    var calls = 0;
    final gateway = AiDocumentVisionGateway(credentialStore: vault,
      sender: (_, _, _) async { calls++; return {}; });
    final config = (await gateway.activeConfiguration())!;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('ai_mode_enabled', false);
    await expectLater(gateway.transcribe(config: config,
      format: AiDocumentFormat.word, jpeg: Uint8List.fromList([1, 2])),
      throwsA(isA<AiTextException>()));
    expect(calls, 0);
  });

  test('empty and oversized images never reach the network', () async {
    SharedPreferences.setMockInitialValues({
      'ai_mode_enabled': true, 'ai_mode_active_provider': 'groq',
    });
    final vault = _KeyVault()..secrets['groq'] = 'secret';
    var calls = 0;
    final gateway = AiDocumentVisionGateway(credentialStore: vault,
      sender: (_, _, _) async { calls++; return {}; });
    final config = (await gateway.activeConfiguration())!;
    await expectLater(gateway.transcribe(config: config,
      format: AiDocumentFormat.word, jpeg: Uint8List(0)),
      throwsA(isA<AiTextException>()));
    await expectLater(gateway.transcribe(config: config,
      format: AiDocumentFormat.word,
      jpeg: Uint8List(AiPageImage.maxUploadBytes + 1)),
      throwsA(isA<AiTextException>()));
    expect(calls, 0);
  });
}
