import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/ai_credential_store.dart';
import '../services/ai_provider_catalog.dart';
import '../theme.dart';

/// Provider credentials are configured here, but no inference request is sent
/// until an individual document feature explicitly implements and requests it.
class AiModeScreen extends StatefulWidget {
  const AiModeScreen({super.key, this.credentialStore});

  final AiCredentialStore? credentialStore;

  @override
  State<AiModeScreen> createState() => _AiModeScreenState();
}

class _AiModeScreenState extends State<AiModeScreen> {
  static const _enabledPreference = 'ai_mode_enabled';
  static const _providerPreference = 'ai_mode_active_provider';

  late final AiCredentialStore _vault =
      widget.credentialStore ?? const SecureAiCredentialStore();
  final Map<String, bool> _hasKeys = {};
  bool _loading = true;
  bool _enabled = false;
  String? _activeId;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = <String, bool>{};
      for (final provider in AiProviderCatalog.providers) {
        keys[provider.id] = await _vault.hasKey(provider.id);
      }
      final active = prefs.getString(_providerPreference);
      final enabled = prefs.getBool(_enabledPreference) ?? false;
      if (!mounted) return;
      setState(() {
        _hasKeys..clear()..addAll(keys);
        _activeId = active;
        _enabled = enabled && (keys[active] ?? false);
        _loading = false;
      });
      if (enabled && !(_hasKeys[active] ?? false)) {
        await prefs.setBool(_enabledPreference, false);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      _notice('Cannot access secure key storage on this device.');
    }
  }

  void _notice(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  Future<void> _changeEnabled(bool value) async {
    if (!(_hasKeys[_activeId] ?? false)) {
      _notice('Save a key and choose a provider first.');
      return;
    }
    setState(() => _enabled = value);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_enabledPreference, value);
    } catch (_) {
      if (mounted) setState(() => _enabled = !value);
      _notice('Could not save the AI Mode setting.');
    }
  }

  Future<void> _select(AiProvider provider) async {
    if (!(_hasKeys[provider.id] ?? false)) {
      await _edit(provider);
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_providerPreference, provider.id);
      if (mounted) setState(() => _activeId = provider.id);
      _notice('${provider.name} selected.');
    } catch (_) {
      _notice('Could not choose this provider.');
    }
  }

  Future<void> _edit(AiProvider provider) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _ProviderKeySheet(
        provider: provider,
        vault: _vault,
        hasSavedKey: _hasKeys[provider.id] ?? false,
      ),
    );
    if (saved == null || !mounted) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (saved && !(_hasKeys[_activeId] ?? false)) {
        await prefs.setString(_providerPreference, provider.id);
      }
      if (!saved && provider.id == _activeId) {
        await prefs.setBool(_enabledPreference, false);
        await prefs.remove(_providerPreference);
      }
      await _refresh();
      _notice(saved ? 'API key saved in encrypted storage.' : 'API key removed.');
    } catch (_) {
      _notice('Unable to update provider settings.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final active = AiProviderCatalog.byId(_activeId ?? '');
    return Scaffold(
      appBar: AppBar(title: const Text('AI Mode')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 32), children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [
                    Color(0xFF063D43), Color(0xFF087F80),
                  ]),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.auto_awesome, color: Color(0xFF9FFFF1), size: 30),
                    SizedBox(height: 10),
                    Text('Your AI, your choice', style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold,
                      fontSize: 22,
                    )),
                    SizedBox(height: 6),
                    Text('Connect your own provider API key. Secrets are '
                      'encrypted on this device and are never stored in '
                      'document files.', style: TextStyle(color: Color(0xFFE3F9F7))),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Card(child: SwitchListTile.adaptive(
                key: const Key('ai-mode-switch'),
                secondary: const Icon(Icons.auto_awesome_outlined, color: dsTeal),
                title: const Text('Enable AI Mode'),
                subtitle: Text(active == null
                    ? 'Choose a provider and save a key'
                    : '${active.name} · ${_hasKeys[_activeId] == true ? 'Key saved' : 'Key required'}'),
                value: _enabled,
                onChanged: (_hasKeys[_activeId] ?? false)
                    ? _changeEnabled : null,
              )),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 10, 4, 12),
                child: Text(
                  'AI document processing is not connected yet. '
                  'Turning this on only saves your preference; it does not '
                  'upload scans or make API calls.',
                  style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
                ),
              ),
              _heading('Providers with free-tier options'),
              for (final provider in AiProviderCatalog.providers.where((p) => p.freeTier))
                _providerTile(provider),
              const SizedBox(height: 18),
              _heading('More AI providers'),
              for (final provider in AiProviderCatalog.providers.where((p) => !p.freeTier))
                _providerTile(provider),
              const SizedBox(height: 16),
              const ListTile(
                contentPadding: EdgeInsets.symmetric(horizontal: 4),
                leading: Icon(Icons.lock_outline, color: dsTeal),
                title: Text('Privacy & billing'),
                subtitle: Text('Provider limits and charges vary. '
                    'A free-tier label is not a promise of unlimited access. '
                    'Your keys remain on your device.'),
              ),
            ]),
    );
  }

  Widget _heading(String title) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 0, 4, 9),
    child: Text(title, style: const TextStyle(
      fontWeight: FontWeight.w700, fontSize: 16,
    )),
  );

  Widget _providerTile(AiProvider provider) {
    final saved = _hasKeys[provider.id] ?? false;
    final active = _activeId == provider.id;
    return Card(
      margin: const EdgeInsets.only(bottom: 7),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(children: [
          ListTile(
            key: Key('ai-provider-${provider.id}'),
            leading: CircleAvatar(
              backgroundColor: dsTeal.withValues(alpha: .13),
              child: const Icon(Icons.hub_outlined, color: dsTeal),
            ),
            title: Text(provider.name,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text('${provider.subtitle}\n${saved ? 'Key saved securely' : 'API key not added'}',
                style: const TextStyle(fontSize: 12)),
            isThreeLine: true,
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _edit(provider),
          ),
          if (saved) Padding(
            padding: const EdgeInsets.fromLTRB(72, 0, 12, 5),
            child: Align(
              alignment: Alignment.centerRight,
              child: active
                  ? const Chip(avatar: Icon(Icons.check_circle, size: 18,
                      color: dsTeal), label: Text('Selected'))
                  : TextButton.icon(
                      key: Key('ai-select-${provider.id}'),
                      onPressed: () => _select(provider),
                      icon: const Icon(Icons.check_circle_outline),
                      label: const Text('Use this provider'),
                    ),
            ),
          ),
        ]),
      ),
    );
  }
}

class _ProviderKeySheet extends StatefulWidget {
  const _ProviderKeySheet({
    required this.provider,
    required this.vault,
    required this.hasSavedKey,
  });

  final AiProvider provider;
  final AiCredentialStore vault;
  final bool hasSavedKey;

  @override
  State<_ProviderKeySheet> createState() => _ProviderKeySheetState();
}

class _ProviderKeySheetState extends State<_ProviderKeySheet> {
  final _keyController = TextEditingController();
  final _accountController = TextEditingController();
  bool _visible = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _keyController.dispose();
    _accountController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_keyController.text.trim().isEmpty) {
      setState(() => _error = 'Enter an API key first.');
      return;
    }
    if (widget.provider.needsAccountId &&
        _accountController.text.trim().isEmpty &&
        !await widget.vault.hasAccountId(widget.provider.id)) {
      setState(() => _error = 'Enter your Cloudflare Account ID.');
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      await widget.vault.saveKey(widget.provider.id, _keyController.text,
        accountId: _accountController.text.trim().isEmpty
            ? null : _accountController.text.trim());
      _keyController.clear();
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) setState(() => _error = 'Unable to save key securely. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove API key?'),
        content: Text('Delete the saved ${widget.provider.name} key from this device?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel')),
          FilledButton(
            key: const Key('ai-confirm-remove'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.vault.deleteKey(widget.provider.id);
      if (mounted) Navigator.of(context).pop(false);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not remove this key.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 8, 20,
          MediaQuery.viewInsetsOf(context).bottom + 24),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(widget.provider.name, style: const TextStyle(
              fontWeight: FontWeight.bold, fontSize: 20)),
          const SizedBox(height: 8),
          Text(widget.hasSavedKey
              ? 'A key is already saved. Enter a new one to replace it.'
              : 'Paste your personal API key to configure this provider.'),
          const SizedBox(height: 16),
          TextField(
            key: Key('ai-key-input-${widget.provider.id}'),
            controller: _keyController,
            obscureText: !_visible,
            autocorrect: false,
            enableSuggestions: false,
            keyboardType: TextInputType.visiblePassword,
            decoration: InputDecoration(
              labelText: 'API key',
              hintText: 'Paste API key',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                tooltip: _visible ? 'Hide API key' : 'Show API key',
                onPressed: () => setState(() => _visible = !_visible),
                icon: Icon(_visible ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined),
              ),
            ),
          ),
          if (widget.provider.needsAccountId) ...[
            const SizedBox(height: 12),
            TextField(
              key: const Key('ai-account-cloudflare'),
              controller: _accountController,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: 'Cloudflare Account ID',
                hintText: widget.hasSavedKey ? 'Leave empty to keep saved ID' : null,
                border: const OutlineInputBorder(),
              ),
            ),
          ],
          if (_error != null) Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(_error!, style: TextStyle(
              color: Theme.of(context).colorScheme.error,
            )),
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: widget.provider.keyPage));
              if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('API key website link copied.')),
              );
            },
            icon: const Icon(Icons.copy_outlined),
            label: const Text('Copy API key website link'),
          ),
          const SizedBox(height: 7),
          FilledButton.icon(
            key: const Key('ai-save-key'),
            onPressed: _busy ? null : _save,
            icon: const Icon(Icons.lock_outline),
            label: Text(widget.hasSavedKey ? 'Replace key' : 'Save key securely'),
          ),
          if (widget.hasSavedKey) TextButton(
            key: const Key('ai-remove-key'),
            onPressed: _busy ? null : _remove,
            child: const Text('Remove saved key'),
          ),
        ]),
      ),
    );
  }
}
