import 'package:docscanner/src/screens/ai_mode_screen.dart';
import 'package:docscanner/src/services/ai_credential_store.dart';
import 'package:docscanner/src/services/ai_provider_catalog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeAiVault implements AiCredentialStore {
  final keys = <String, String>{};
  final accounts = <String, String>{};

  @override
  Future<bool> hasKey(String id) async => keys.containsKey(id);

  @override
  Future<String?> readKey(String id) async => keys[id];

  @override
  Future<bool> hasAccountId(String id) async => accounts.containsKey(id);

  @override
  Future<void> saveKey(String id, String key, {String? accountId}) async {
    keys[id] = key.trim();
    if (accountId != null) accounts[id] = accountId;
  }

  @override
  Future<void> deleteKey(String id) async {
    keys.remove(id);
    accounts.remove(id);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('provider catalog has required and optional entries', () {
    expect(AiProviderCatalog.byId('gemini')?.name, contains('Google'));
    expect(AiProviderCatalog.byId('groq')?.name, 'Groq Cloud');
    expect(AiProviderCatalog.byId('openrouter')?.name, 'OpenRouter');
    expect(AiProviderCatalog.byId('cloudflare')?.needsAccountId, isTrue);
    expect(AiProviderCatalog.byId('openai')?.freeTier, isFalse);
    expect(AiProviderCatalog.providers.length, greaterThanOrEqualTo(10));
  });

  testWidgets('key entry is obscured, enables provider without leaking secret',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 980));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final vault = _FakeAiVault();
    await tester.pumpWidget(MaterialApp(home: AiModeScreen(credentialStore: vault)));
    await tester.pumpAndSettle();

    expect(find.text('Providers with free-tier options'), findsOneWidget);
    expect(tester.widget<SwitchListTile>(find.byKey(const Key('ai-mode-switch')))
        .onChanged, isNull);

    await tester.tap(find.byKey(const Key('ai-provider-gemini')));
    await tester.pumpAndSettle();
    final field = find.byKey(const Key('ai-key-input-gemini'));
    expect(tester.widget<TextField>(field).obscureText, isTrue);
    await tester.enterText(field, 'unit_test_secret_123');
    await tester.tap(find.byKey(const Key('ai-save-key')));
    await tester.pumpAndSettle();

    expect(vault.keys['gemini'], 'unit_test_secret_123');
    expect(find.text('unit_test_secret_123'), findsNothing);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('ai_mode_active_provider'), 'gemini');
    expect(prefs.getKeys().where((k) => k.contains('key')), isEmpty);
    expect(prefs.getBool('ai_mode_enabled'), isNull);
    expect(tester.widget<SwitchListTile>(find.byKey(const Key('ai-mode-switch')))
        .onChanged, isNotNull);

    await tester.tap(find.byKey(const Key('ai-mode-switch')));
    await tester.pumpAndSettle();
    expect(prefs.getBool('ai_mode_enabled'), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('removing selected key disables AI Mode', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 980));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final vault = _FakeAiVault()..keys['groq'] = 'existing_secret';
    SharedPreferences.setMockInitialValues({
      'ai_mode_active_provider': 'groq',
      'ai_mode_enabled': true,
    });
    await tester.pumpWidget(MaterialApp(home: AiModeScreen(credentialStore: vault)));
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(find.byKey(const Key('ai-mode-switch')))
        .value, isTrue);
    await tester.scrollUntilVisible(
      find.byKey(const Key('ai-provider-groq')), 180,
    );
    await tester.ensureVisible(find.byKey(const Key('ai-provider-groq')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ai-provider-groq')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ai-remove-key')));
    await tester.pumpAndSettle();
    expect(find.text('Remove API key?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('ai-confirm-remove')));
    await tester.pumpAndSettle();

    expect(vault.keys.containsKey('groq'), isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('ai_mode_active_provider'), isNull);
    expect(prefs.getBool('ai_mode_enabled'), isFalse);
    expect(tester.widget<SwitchListTile>(find.byKey(const Key('ai-mode-switch')))
        .value, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('selected text model ID can be changed without replacing key',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 980));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final vault = _FakeAiVault()..keys['groq'] = 'saved_key';
    SharedPreferences.setMockInitialValues({
      'ai_mode_active_provider': 'groq',
      'ai_mode_enabled': true,
    });
    await tester.pumpWidget(MaterialApp(home: AiModeScreen(
      credentialStore: vault,
    )));
    await tester.pumpAndSettle();
    expect(find.text('llama-3.3-70b-versatile'), findsOneWidget);
    await tester.tap(find.byKey(const Key('ai-model-tile')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('ai-model-editor')),
        'openai/gpt-oss-120b');
    await tester.tap(find.byKey(const Key('ai-save-model')));
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('ai_model_groq'), 'openai/gpt-oss-120b');
    expect(vault.keys['groq'], 'saved_key');
  });

  testWidgets('vision model is configured independently of text model',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 980));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final vault = _FakeAiVault()..keys['groq'] = 'saved_key';
    SharedPreferences.setMockInitialValues({
      'ai_mode_active_provider': 'groq', 'ai_mode_enabled': true,
    });
    await tester.pumpWidget(MaterialApp(home: AiModeScreen(
      credentialStore: vault)));
    await tester.pumpAndSettle();
    expect(find.text('qwen/qwen3.8-27b'), findsOneWidget);
    await tester.tap(find.byKey(const Key('ai-vision-model-tile')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('ai-vision-model-editor')),
      'qwen/custom-vision');
    await tester.tap(find.byKey(const Key('ai-save-vision-model')));
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('ai_vision_model_groq'), 'qwen/custom-vision');
    expect(prefs.getString('ai_model_groq'), isNull);
    expect(vault.keys['groq'], 'saved_key');
  });

  testWidgets('Cloudflare requires Account ID for first key', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 980));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final vault = _FakeAiVault();
    await tester.pumpWidget(MaterialApp(home: AiModeScreen(credentialStore: vault)));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('ai-provider-cloudflare')), 210,
    );
    await tester.ensureVisible(find.byKey(const Key('ai-provider-cloudflare')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ai-provider-cloudflare')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('ai-key-input-cloudflare')),
        'test-token');
    await tester.tap(find.byKey(const Key('ai-save-key')));
    await tester.pump();
    expect(find.text('Enter your Cloudflare Account ID.'), findsOneWidget);
    expect(vault.keys, isEmpty);
    await tester.enterText(find.byKey(const Key('ai-account-cloudflare')),
        'test-account');
    await tester.tap(find.byKey(const Key('ai-save-key')));
    await tester.pumpAndSettle();
    expect(vault.keys['cloudflare'], 'test-token');
    expect(vault.accounts['cloudflare'], 'test-account');
    expect(tester.takeException(), isNull);
  });
}
