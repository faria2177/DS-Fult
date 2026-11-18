import 'dart:convert';

import 'ai_provider_catalog.dart';

/// One API key found in an imported key file.
class ImportedAiKey {
  const ImportedAiKey(
      {required this.providerId, required this.key, this.accountId});

  final String providerId;
  final String key;

  /// Cloudflare Account ID, when the file provides one.
  final String? accountId;

  /// Safe to show on screen: first 4 and last 4 characters only.
  String get masked => key.length <= 10
      ? '•' * key.length
      : '${key.substring(0, 4)}…${key.substring(key.length - 4)}';
}

/// Result of reading a key file.
class AiKeyFileContents {
  const AiKeyFileContents(this.keys, this.problems);

  /// At most one key per provider (the last one in the file wins).
  final List<ImportedAiKey> keys;

  /// Lines that could not be used, already worded for the user.
  final List<String> problems;
}

/// Reads API keys for the AI Mode providers from a text, .env or JSON file.
///
/// Accepted, freely mixed:
///   gemini = AIza...            Groq: gsk_...       OPENAI_API_KEY="sk-proj-..."
///   export ANTHROPIC_API_KEY=sk-ant-...             CLOUDFLARE_ACCOUNT_ID=abc
///   a provider name on one line and its key on the next line
///   a bare key whose prefix identifies the provider (AIza, gsk_, sk-or-, hf_,
///   sk-ant-, xai-, sk-proj-)
///   {"gemini": "AIza...", "cloudflare": {"key": "...", "accountId": "..."}}
/// Blank lines and lines starting with # or // are ignored.
abstract final class AiKeyFileParser {
  /// Longest key file read (key files are tiny; this blocks binary files).
  static const maxBytes = 64 * 1024;

  static const _aliases = <String, List<String>>{
    'gemini': ['gemini', 'google', 'googleai', 'aistudio', 'googleaistudio',
      'googlegemini'],
    'groq': ['groq', 'groqcloud'],
    'openrouter': ['openrouter'],
    'cloudflare': ['cloudflare', 'cf', 'workersai', 'cloudflareworkersai',
      'cloudflareai'],
    'huggingface': ['huggingface', 'hf', 'hugging'],
    'mistral': ['mistral', 'mistralai'],
    'deepseek': ['deepseek'],
    'cohere': ['cohere'],
    'openai': ['openai', 'chatgpt', 'gpt'],
    'anthropic': ['anthropic', 'claude'],
    'xai': ['xai', 'grok'],
    'together': ['together', 'togetherai'],
    'deepai': ['deepai', 'deep-ai', 'deep_ai'],
  };

  static const _suffixes = ['apikey', 'apitoken', 'accesstoken', 'token',
    'secretkey', 'secret', 'key', 'api'];

  static final _labelled = RegExp(
      r'^(?:export\s+)?([A-Za-z][A-Za-z0-9 _.()\-/]{0,60}?)\s*[:=]\s*(.*)$');

  static AiKeyFileContents parse(String text) {
    final cleaned = text.replaceFirst('﻿', '').trim();
    if (cleaned.startsWith('{')) {
      try {
        final data = jsonDecode(cleaned);
        if (data is Map) return _fromJson(data);
      } catch (_) {
        // Not valid JSON: read it line by line instead.
      }
    }
    return _fromLines(cleaned);
  }

  static AiKeyFileContents _fromLines(String text) {
    final keys = <String, String>{};
    final accounts = <String, String>{};
    final problems = <String>[];
    String? pendingProvider;
    final lines = const LineSplitter().convert(text);
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      final number = i + 1;
      if (line.isEmpty || line.startsWith('#') || line.startsWith('//')) {
        continue;
      }
      final match = _labelled.firstMatch(line);
      if (match != null && !_looksLikeBareKey(line)) {
        final label = _normalise(match.group(1)!);
        final value = _cleanValue(match.group(2)!);
        final provider = _providerFor(label);
        if (provider == null) {
          problems.add('Line $number: "${match.group(1)!.trim()}" is not a '
              'supported AI provider.');
          continue;
        }
        if (value.isEmpty) {
          // "Gemini:" alone: the key may be on the next line.
          pendingProvider = provider;
          continue;
        }
        if (_isAccountLabel(label)) {
          if (provider == 'cloudflare' && _plausibleAccount(value)) {
            accounts[provider] = value;
          } else {
            problems.add('Line $number: account ID is only used for '
                'Cloudflare.');
          }
          continue;
        }
        if (!_plausibleKey(value)) {
          problems.add('Line $number: the ${_name(provider)} key does not '
              'look like an API key.');
          continue;
        }
        keys[provider] = value;
        pendingProvider = null;
        continue;
      }
      // A provider name on its own line.
      // (Names are short or have spaces; a long unbroken string is a key.)
      final nameLike = line.contains(' ') || line.length < 16;
      final alone = nameLike ? _providerFor(_normalise(line)) : null;
      if (alone != null && !_looksLikeBareKey(line)) {
        pendingProvider = alone;
        continue;
      }
      final value = _cleanValue(line);
      if (!_plausibleKey(value)) {
        problems.add('Line $number: not recognised as an API key.');
        continue;
      }
      final provider = pendingProvider ?? _providerFromPrefix(value);
      pendingProvider = null;
      if (provider == null) {
        problems.add('Line $number: cannot tell which AI this key is for. '
            'Write it as provider=key (for example mistral=...).');
        continue;
      }
      keys[provider] = value;
    }
    return _result(keys, accounts, problems);
  }

  static AiKeyFileContents _fromJson(Map<dynamic, dynamic> data) {
    final keys = <String, String>{};
    final accounts = <String, String>{};
    final problems = <String>[];
    data.forEach((rawLabel, rawValue) {
      final label = _normalise('$rawLabel');
      final provider = _providerFor(label);
      if (provider == null) {
        problems.add('"$rawLabel" is not a supported AI provider.');
        return;
      }
      String? key;
      String? account;
      if (rawValue is String) {
        if (_isAccountLabel(label)) {
          account = _cleanValue(rawValue);
        } else {
          key = _cleanValue(rawValue);
        }
      } else if (rawValue is Map) {
        for (final entry in rawValue.entries) {
          final field = _normalise('${entry.key}');
          final value = entry.value is String
              ? _cleanValue(entry.value as String) : '';
          if (field.contains('account')) {
            account = value;
          } else if (field.isEmpty || _suffixes.contains(field) ||
              field == 'value') {
            key = value;
          }
        }
      }
      if (account != null && account.isNotEmpty) {
        if (provider == 'cloudflare' && _plausibleAccount(account)) {
          accounts[provider] = account;
        } else {
          problems.add('"$rawLabel": account ID is only used for Cloudflare.');
        }
      }
      if (key != null) {
        if (_plausibleKey(key)) {
          keys[provider] = key;
        } else {
          problems.add('"$rawLabel": the key does not look like an API key.');
        }
      }
    });
    return _result(keys, accounts, problems);
  }

  static AiKeyFileContents _result(Map<String, String> keys,
      Map<String, String> accounts, List<String> problems) {
    final found = <ImportedAiKey>[];
    for (final provider in AiProviderCatalog.providers) {
      final key = keys[provider.id];
      if (key == null) {
        if (accounts.containsKey(provider.id)) {
          problems.add('${provider.name}: an account ID was found but no key.');
        }
        continue;
      }
      found.add(ImportedAiKey(providerId: provider.id, key: key,
          accountId: accounts[provider.id]));
    }
    return AiKeyFileContents(found, problems);
  }

  /// Lower-case letters and digits only, without trailing "api key" words.
  static String _normalise(String label) {
    var text = label.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    var changed = true;
    while (changed && text.isNotEmpty) {
      changed = false;
      for (final suffix in _suffixes) {
        if (text.length > suffix.length && text.endsWith(suffix)) {
          text = text.substring(0, text.length - suffix.length);
          changed = true;
          break;
        }
      }
    }
    return text;
  }

  static bool _isAccountLabel(String label) =>
      label.contains('account') || label.endsWith('accid');

  static String? _providerFor(String label) {
    final base = label
        .replaceAll('accountid', '')
        .replaceAll('account', '');
    if (base.isEmpty) return null;
    for (final entry in _aliases.entries) {
      if (entry.value.contains(base)) return entry.key;
    }
    // "Google AI Studio (Gemini)", "My Groq key 2": longest alias inside.
    String? best;
    var bestLength = 0;
    for (final entry in _aliases.entries) {
      for (final alias in entry.value) {
        if (alias.length >= 4 && alias.length > bestLength &&
            base.contains(alias)) {
          best = entry.key;
          bestLength = alias.length;
        }
      }
    }
    return best;
  }

  static String? _providerFromPrefix(String key) {
    if (key.startsWith('AIza')) return 'gemini';
    if (key.startsWith('gsk_')) return 'groq';
    if (key.startsWith('sk-or-')) return 'openrouter';
    if (key.startsWith('hf_')) return 'huggingface';
    if (key.startsWith('sk-ant-')) return 'anthropic';
    if (key.startsWith('xai-')) return 'xai';
    if (key.startsWith('sk-proj-') || key.startsWith('sk-svcacct-')) {
      return 'openai';
    }
    return null;
  }

  static bool _looksLikeBareKey(String line) {
    final value = _cleanValue(line);
    return _providerFromPrefix(value) != null && !value.contains('=');
  }

  static String _cleanValue(String raw) {
    var value = raw.trim();
    // Drop a trailing comment ("KEY=abc  # personal").
    final comment = RegExp(r'\s+#.*$').firstMatch(value);
    if (comment != null) value = value.substring(0, comment.start).trim();
    if (value.endsWith(',')) value = value.substring(0, value.length - 1);
    if (value.length >= 2 &&
        ((value.startsWith('"') && value.endsWith('"')) ||
            (value.startsWith("'") && value.endsWith("'")))) {
      value = value.substring(1, value.length - 1).trim();
    }
    if (value.toLowerCase().startsWith('bearer ')) {
      value = value.substring(7).trim();
    }
    return value;
  }

  static bool _plausibleKey(String value) =>
      value.length >= 16 && value.length <= 400 &&
      RegExp(r'^[\x21-\x7E]+$').hasMatch(value);

  static bool _plausibleAccount(String value) =>
      RegExp(r'^[A-Za-z0-9]{8,64}$').hasMatch(value);

  static String _name(String providerId) =>
      AiProviderCatalog.byId(providerId)?.name ?? providerId;
}
