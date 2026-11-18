import 'package:docscanner/src/screens/ai_mode_screen.dart';
import 'package:docscanner/src/services/ai_credential_store.dart';
import 'package:docscanner/src/services/ai_text_gateway.dart';
import 'package:flutter/material.dart';
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
  Future<void> deleteKey(String id) async => secrets.remove(id);
}

Map<String, dynamic> chat(String text) =>
    {'choices': [{'message': {'content': text}}]};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a failing model falls back to the next model, then provider',
      () async {
    final vault = _Vault()
      ..secrets['openrouter'] = 'k1'
      ..secrets['deepai'] = 'k2';
    SharedPreferences.setMockInitialValues({
      'ai_mode_enabled': true, 'ai_mode_active_provider': 'openrouter',
      'ai_model_openrouter': 'a/one:free',
      'ai_models_openrouter': ['b/two:free'],
    });
    final tried = <String>[];
    final gateway = AiTextGateway(credentialStore: vault,
      sender: (url, headers, body) async {
        if (url.host == 'openrouter.ai') {
          tried.add(body['model'] as String);
          throw const AiTextException('Provider rate limit reached. Try later.');
        }
        tried.add(url.host);
        expect(headers['api-key'], 'k2');
        expect(headers['Content-Type'], AiTextGateway.formContentType);
        expect(body['text'], contains('helo wrld'));
        return {'output': 'hello world'};
      });
    final config = (await gateway.activeConfiguration())!;
    expect((await gateway.fallbackProviders(config)).single.providerId,
        'deepai');
    expect(await gateway.rewrite(config: config, task: AiTextTask.polish,
        text: 'helo wrld'), 'hello world');
    expect(tried, ['a/one:free', 'b/two:free', 'api.deepai.org']);
    expect(gateway.lastUsed!.providerId, 'deepai');
  });

  test('with auto-switch off only the chosen model is tried', () async {
    final vault = _Vault()
      ..secrets['groq'] = 'k1'
      ..secrets['gemini'] = 'k2';
    SharedPreferences.setMockInitialValues({
      'ai_mode_enabled': true, 'ai_mode_active_provider': 'groq',
      'ai_auto_switch': false,
    });
    var calls = 0;
    final gateway = AiTextGateway(credentialStore: vault,
      sender: (_, _, _) async {
        calls++;
        throw const AiTextException('API key rejected or access denied.');
      });
    final config = (await gateway.activeConfiguration())!;
    await expectLater(gateway.rewrite(config: config,
        task: AiTextTask.proofread, text: 'x y'),
      throwsA(isA<AiTextException>().having((e) => e.message, 'message',
          'API key rejected or access denied.')));
    expect(calls, 1);
  });

  test('check reports working and failing APIs', () async {
    final vault = _Vault()
      ..secrets['groq'] = 'k1'
      ..secrets['openrouter'] = 'k2';
    SharedPreferences.setMockInitialValues({});
    final gateway = AiTextGateway(credentialStore: vault,
      sender: (url, _, _) async {
        if (url.host == 'api.groq.com') return chat('OK');
        throw const AiTextException('Provider returned HTTP 404.');
      });
    final good = await gateway.check('groq');
    expect(good.ok, isTrue);
    expect(good.modelId, 'llama-3.3-70b-versatile');
    final bad = await gateway.check('openrouter', modelId: 'x/y:free');
    expect(bad.ok, isFalse);
    expect(bad.message, 'Provider returned HTTP 404.');
  });

  test('free OpenRouter models are picked from the public list', () {
    final ids = AiTextGateway.parseOpenRouterFreeModels({'data': [
      {'id': 'meta/llama:free', 'pricing': {'prompt': '0.1'}},
      {'id': 'qwen/qwen3', 'pricing': {'prompt': '0', 'completion': '0'}},
      {'id': 'openai/gpt', 'pricing': {'prompt': '0.002', 'completion': '1'}},
      {'id': 'bad id with spaces:free'},
    ]});
    expect(ids, ['meta/llama:free', 'qwen/qwen3']);
  });

  testWidgets('AI Mode checks APIs and adds free OpenRouter models',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({
      'ai_mode_enabled': true, 'ai_mode_active_provider': 'openrouter',
    });
    final vault = _Vault()
      ..secrets['openrouter'] = 'k'
      ..secrets['deepai'] = 'd';
    await tester.pumpWidget(MaterialApp(home: AiModeScreen(
      credentialStore: vault,
      textSender: (url, _, _) async {
        if (url.host == 'api.deepai.org') return {'output': 'OK'};
        throw const AiTextException('Provider rate limit reached. Try later.');
      },
      loadFreeModels: () async => ['google/gemma:free', 'meta/llama:free'],
    )));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('ai-auto-switch')), findsOneWidget);
    await tester.tap(find.byKey(const Key('ai-check-apis')));
    await tester.pumpAndSettle();
    expect(find.text('1 of 2 working'), findsOneWidget);
    expect(find.textContaining('rate limit'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('ai-manage-models')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ai-browse-free-models')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('meta/llama:free'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('ai-add-free-models')));
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('ai_models_openrouter'), ['meta/llama:free']);
    expect(find.byKey(const Key('ai-model-row-meta/llama:free')),
        findsOneWidget);
  });
}
