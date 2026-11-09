import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Secrets never enter SharedPreferences, document JSON, logs or GitHub.
/// The OS-backed vault encrypts values at rest; uninstalling may erase keys.
abstract class AiCredentialStore {
  Future<bool> hasKey(String providerId);
  Future<void> saveKey(String providerId, String apiKey,
      {String? accountId});
  Future<void> deleteKey(String providerId);
  Future<bool> hasAccountId(String providerId);
}

class SecureAiCredentialStore implements AiCredentialStore {
  const SecureAiCredentialStore();

  static const _vault = FlutterSecureStorage(
    aOptions: AndroidOptions(storageNamespace: 'docscanner_ai_mode'),
  );

  static String _key(String providerId) => 'ai_key_$providerId';
  static String _account(String providerId) => 'ai_account_$providerId';

  @override
  Future<bool> hasKey(String providerId) async =>
      (await _vault.containsKey(key: _key(providerId)));

  @override
  Future<bool> hasAccountId(String providerId) async =>
      (await _vault.containsKey(key: _account(providerId)));

  @override
  Future<void> saveKey(String providerId, String apiKey,
      {String? accountId}) async {
    final normalized = apiKey.trim();
    if (normalized.isEmpty) {
      throw const FormatException('Enter an API key to save.');
    }
    // Store the account identifier first so a failed key write does not
    // replace the previously valid secret.
    if (accountId != null) {
      if (accountId.trim().isEmpty) {
        throw const FormatException('Enter a Cloudflare Account ID.');
      }
      await _vault.write(key: _account(providerId),
        value: accountId.trim());
    }
    await _vault.write(key: _key(providerId), value: normalized);
  }

  @override
  Future<void> deleteKey(String providerId) async {
    await _vault.delete(key: _key(providerId));
    await _vault.delete(key: _account(providerId));
  }
}
