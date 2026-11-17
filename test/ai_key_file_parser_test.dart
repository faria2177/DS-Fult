import 'package:docscanner/src/services/ai_key_file_parser.dart';
import 'package:flutter_test/flutter_test.dart';

// Obviously fake test values, built at run time so they can never be
// mistaken for real credentials.
final _gemini = 'AIza${'TESTONLY' * 4}';
final _groq = 'gsk_${'TESTONLY' * 5}';
final _openrouter = 'sk-or-v1-${'TESTONLY' * 4}';
final _openai = 'sk-proj-${'TESTONLY' * 4}';
final _mistral = 'test${'ONLY' * 7}';

Map<String, String> _keys(String text) => {
  for (final key in AiKeyFileParser.parse(text).keys) key.providerId: key.key,
};

void main() {
  test('provider=key and Provider: key lines', () {
    final keys = _keys('''
gemini = $_gemini
Groq: $_groq
OpenRouter=$_openrouter
mistral = "$_mistral"
''');
    expect(keys, {'gemini': _gemini, 'groq': _groq,
        'openrouter': _openrouter, 'mistral': _mistral});
  });

  test('.env files with export, quotes and comments', () {
    final result = AiKeyFileParser.parse('''
# my keys
export GEMINI_API_KEY="$_gemini"
OPENAI_API_KEY='$_openai'   # work account
HF_TOKEN=hf_${'TESTONLY' * 4}
CLOUDFLARE_API_TOKEN=cf${'TESTONLY' * 4}
CLOUDFLARE_ACCOUNT_ID=testaccount0001
''');
    final keys = {for (final k in result.keys) k.providerId: k};
    expect(keys['gemini']!.key, _gemini);
    expect(keys['openai']!.key, _openai);
    expect(keys['huggingface']!.key, 'hf_${'TESTONLY' * 4}');
    expect(keys['cloudflare']!.accountId, 'testaccount0001');
    expect(result.problems, isEmpty);
  });

  test('bare keys are matched by their prefix', () {
    expect(_keys('$_gemini\n$_groq\n$_openrouter\n$_openai'), {
      'gemini': _gemini, 'groq': _groq, 'openrouter': _openrouter,
      'openai': _openai,
    });
  });

  test('a provider name on one line and its key on the next', () {
    expect(_keys('Google AI Studio (Gemini)\n$_gemini\n\nMistral AI\n$_mistral'),
        {'gemini': _gemini, 'mistral': _mistral});
  });

  test('JSON, flat and nested', () {
    final result = AiKeyFileParser.parse('''
{"gemini": "$_gemini",
 "anthropic": {"apiKey": "sk-ant-${'TESTONLY' * 4}"},
 "cloudflare": {"key": "cf${'TESTONLY' * 3}", "accountId": "testaccount0002"}}
''');
    final keys = {for (final k in result.keys) k.providerId: k};
    expect(keys.keys, containsAll(['gemini', 'anthropic', 'cloudflare']));
    expect(keys['cloudflare']!.accountId, 'testaccount0002');
  });

  test('unknown and unlabelled keys are reported, not guessed', () {
    final result = AiKeyFileParser.parse('''
myservice=$_mistral
$_mistral
gemini=short
''');
    expect(result.keys, isEmpty);
    expect(result.problems, hasLength(3));
    expect(result.problems[1], contains('cannot tell which AI'));
  });

  test('the last key for a provider wins and keys are masked for display', () {
    final result = AiKeyFileParser.parse('gemini=AIza${'OLD' * 8}\n'
        'gemini=$_gemini');
    expect(result.keys.single.key, _gemini);
    expect(result.keys.single.masked, 'AIza…ONLY');
    expect(result.keys.single.masked, isNot(contains('TESTONLYTEST')));
  });
}
