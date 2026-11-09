import 'package:docscanner/src/services/ai_credential_store.dart';
import 'package:docscanner/src/services/ai_text_gateway.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Vault implements AiCredentialStore {
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

  test('disabled AI Mode never touches network or reads credentials', () async {
    final vault = _Vault()..secrets['gemini'] = 'secret';
    var calls = 0;
    final gateway = AiTextGateway(credentialStore: vault,
      sender: (_, _, _) async {
        calls++;
        return {};
      });
    expect(await gateway.activeConfiguration(), isNull);
    expect(calls, 0);
  });

  for (final id in ['gemini', 'groq', 'openrouter']) {
    test('$id sends only requested OCR text to a fixed HTTPS endpoint', () async {
      final vault = _Vault()..secrets[id] = 'super-secret-$id';
      SharedPreferences.setMockInitialValues({
        'ai_mode_enabled': true, 'ai_mode_active_provider': id,
      });
      Uri? capturedUrl;
      Map<String, String>? capturedHeaders;
      Map<String, dynamic>? capturedBody;
      var count = 0;
      final gateway = AiTextGateway(credentialStore: vault,
        sender: (url, headers, body) async {
          count++;
          capturedUrl = url;
          capturedHeaders = headers;
          capturedBody = body;
          return id == 'gemini'
              ? {'candidates': [{'content': {'parts': [
                  {'text': 'Corrected text.'}
                ]}}]}
              : {'choices': [{'message': {'content': 'Corrected text.'}}]};
        });
      final config = await gateway.activeConfiguration();
      expect(config, isNotNull);
      expect(count, 0, reason: 'Selecting a provider must not send data');
      expect(await gateway.rewrite(config: config!,
        task: AiTextTask.proofread, text: 'Ocr text.'), 'Corrected text.');
      expect(count, 1);
      expect(capturedUrl!.scheme, 'https');
      expect(capturedUrl!.host, id == 'gemini'
          ? 'generativelanguage.googleapis.com'
          : id == 'groq' ? 'api.groq.com' : 'openrouter.ai');
      expect(capturedHeaders.toString(), contains('super-secret-$id'));
      expect(capturedBody.toString(), contains('Ocr text.'));
      expect(capturedBody.toString(), isNot(contains('/camera/scan.jpg')));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys().where((key) => key.contains('secret')), isEmpty);
    });
  }

  test('disabled or switched provider rejects a stale approved request', () async {
    final vault = _Vault()..secrets['groq'] = 'secret';
    SharedPreferences.setMockInitialValues({
      'ai_mode_enabled': true, 'ai_mode_active_provider': 'groq',
    });
    var calls = 0;
    final gateway = AiTextGateway(credentialStore: vault,
      sender: (_, _, _) async { calls++; return {}; });
    final config = (await gateway.activeConfiguration())!;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('ai_mode_enabled', false);
    await expectLater(gateway.rewrite(config: config,
      task: AiTextTask.proofread, text: 'Hello'),
      throwsA(isA<AiTextException>()));
    expect(calls, 0);
  });

  test('oversize text is rejected before an external request', () async {
    final vault = _Vault()..secrets['openrouter'] = 'key';
    SharedPreferences.setMockInitialValues({
      'ai_mode_enabled': true, 'ai_mode_active_provider': 'openrouter',
    });
    var calls = 0;
    final gateway = AiTextGateway(credentialStore: vault,
      sender: (_, _, _) async { calls++; return {}; });
    final config = (await gateway.activeConfiguration())!;
    await expectLater(gateway.rewrite(config: config,
      task: AiTextTask.tableCleanup,
      text: List.filled(12001, 'x').join()),
      throwsA(isA<AiTextException>()));
    expect(calls, 0);
  });

  test('an unsupported provider key does not expose active AI execution', () async {
    final vault = _Vault()..secrets['anthropic'] = 'key';
    SharedPreferences.setMockInitialValues({
      'ai_mode_enabled': true, 'ai_mode_active_provider': 'anthropic',
    });
    final gateway = AiTextGateway(credentialStore: vault,
      sender: (_, _, _) async => {});
    expect(await gateway.activeConfiguration(), isNull);
  });
}
