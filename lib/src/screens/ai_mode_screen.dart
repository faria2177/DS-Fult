import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/ai_credential_store.dart';
import '../services/ai_key_file_parser.dart';
import '../services/ai_provider_catalog.dart';
import '../services/ai_text_gateway.dart';
import '../theme.dart';

/// Provider credentials are configured here, but no inference request is sent
/// until an individual document feature explicitly implements and requests it.
typedef AiLinkOpener = Future<bool> Function(Uri uri);

class AiModeScreen extends StatefulWidget {
  const AiModeScreen({super.key, this.credentialStore, this.openExternalLink,
      this.pickKeyFile, this.textSender, this.loadFreeModels});

  final AiCredentialStore? credentialStore;
  /// Test seam for "Check APIs" requests.
  final AiTextSender? textSender;
  /// Test seam for "Browse free models" (OpenRouter public model list).
  final Future<List<String>> Function()? loadFreeModels;
  /// Test seam: returns the chosen key file's text, or null if cancelled.
  final Future<String?> Function()? pickKeyFile;
  /// Test seam; production always uses the system browser for official sites.
  final AiLinkOpener? openExternalLink;

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
  String? _modelId;
  String? _visionModelId;
  bool _autoSwitch = true;
  List<String> _models = const [];
  bool _checking = false;

  late final AiTextGateway _gateway = AiTextGateway(
      credentialStore: _vault, sender: widget.textSender);

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
      final supported = AiProviderCatalog.textModels.containsKey(active);
      if (!mounted) return;
      setState(() {
        _hasKeys..clear()..addAll(keys);
        _activeId = active;
        _enabled = enabled && supported && (keys[active] ?? false);
        _modelId = prefs.getString('ai_model_$active') ??
            AiProviderCatalog.textModels[active];
        _visionModelId = prefs.getString('ai_vision_model_$active') ??
            AiProviderCatalog.visionModels[active];
        _autoSwitch = prefs.getBool(AiTextGateway.autoSwitchPreference) ?? true;
        _loading = false;
      });
      final models = active == null ? const <String>[]
          : await AiTextGateway.modelsFor(active, prefs: prefs);
      if (mounted) setState(() => _models = models);
      if (enabled && (!supported || !(_hasKeys[active] ?? false))) {
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

  Future<void> _openKeyPage(AiProvider provider) async {
    final uri = Uri.tryParse(provider.keyPage);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      _notice('This provider does not have a valid official key link.');
      return;
    }
    try {
      final opened = await (widget.openExternalLink?.call(uri) ??
          launchUrl(uri, mode: LaunchMode.externalApplication));
      if (opened) return;
    } catch (_) {
      // A browser may not be installed; make the link copyable instead.
    }
    await Clipboard.setData(ClipboardData(text: uri.toString()));
    _notice('Could not open the browser. API key link copied instead.');
  }

  Widget _keyHelpRow(String providerId, String instruction) {
    final provider = AiProviderCatalog.byId(providerId)!;
    return ListTile(
      dense: true,
      title: Text(provider.name, style: const TextStyle(
        fontWeight: FontWeight.w600)),
      subtitle: Text(instruction),
      trailing: const Icon(Icons.open_in_new, size: 19, color: dsTeal),
      onTap: () => _openKeyPage(provider),
      key: Key('ai-help-$providerId'),
    );
  }

  Future<void> _changeEnabled(bool value) async {
    if (!(_hasKeys[_activeId] ?? false) ||
        !AiProviderCatalog.textModels.containsKey(_activeId)) {
      _notice('Choose Google AI Studio, Groq or OpenRouter with a saved key.');
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
      if (!AiProviderCatalog.textModels.containsKey(provider.id)) {
        await prefs.setBool(_enabledPreference, false);
      }
      await _refresh();
      _notice('${provider.name} selected.');
    } catch (_) {
      _notice('Could not choose this provider.');
    }
  }

  Future<void> _editModel({bool vision = false}) async {
    final active = _activeId;
    if (active == null || !AiProviderCatalog.textModels.containsKey(active)) return;
    final defaults = vision ? AiProviderCatalog.visionModels
        : AiProviderCatalog.textModels;
    var draft = vision ? (_visionModelId ?? defaults[active]!)
        : (_modelId ?? defaults[active]!);
    final next = await showDialog<String>(context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(vision ? 'Document vision model ID' : 'Text AI model ID'),
        content: TextFormField(
          key: Key(vision ? 'ai-vision-model-editor' : 'ai-model-editor'),
          initialValue: draft,
          autocorrect: false,
          decoration: const InputDecoration(
            labelText: 'Provider model ID',
            helperText: 'Check your provider for supported models',
          ),
          onChanged: (text) => draft = text,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel')),
          FilledButton(key: Key(vision ? 'ai-save-vision-model' : 'ai-save-model'),
            onPressed: () => Navigator.pop(dialogContext, draft),
            child: const Text('Save')),
        ],
      ));
    if (!mounted || next == null) return;
    final normalized = next.trim();
    if (!RegExp(r'^[A-Za-z0-9._:/-]{2,110}$').hasMatch(normalized)) {
      _notice('Invalid model ID. Use letters, numbers, /, :, - or _.');
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(vision ? 'ai_vision_model_$active'
        : 'ai_model_$active', normalized);
    await _refresh();
    _notice(vision ? 'Vision model ID saved.' : 'Text model ID saved.');
  }

  Future<void> _setAutoSwitch(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AiTextGateway.autoSwitchPreference, value);
    if (mounted) setState(() => _autoSwitch = value);
  }

  /// Sends a tiny "reply OK" prompt to every saved text provider and model.
  Future<void> _checkApis() async {
    final prefs = await SharedPreferences.getInstance();
    final targets = <(String, String)>[];
    for (final id in AiProviderCatalog.textModels.keys) {
      if (_hasKeys[id] != true) continue;
      for (final model in await AiTextGateway.modelsFor(id, prefs: prefs)) {
        targets.add((id, model));
      }
    }
    if (!mounted) return;
    if (targets.isEmpty) {
      _notice('Save an API key for Google AI Studio, Groq, OpenRouter or '
          'DeepAI first.');
      return;
    }
    setState(() => _checking = true);
    final results = <AiHealthResult>[];
    for (final (id, model) in targets) {
      results.add(await _gateway.check(id, modelId: model));
      if (!mounted) return;
    }
    setState(() => _checking = false);
    final working = results.where((r) => r.ok).length;
    await showDialog<void>(context: context, builder: (dialogContext) =>
      AlertDialog(
        title: Text('$working of ${results.length} working'),
        content: SizedBox(width: double.maxFinite, child: ListView(
          shrinkWrap: true,
          children: [
            for (final r in results) ListTile(
              key: Key('ai-check-${r.providerId}-${r.modelId}'),
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(r.ok ? Icons.check_circle : Icons.error_outline,
                  color: r.ok ? Colors.green : Colors.redAccent),
              title: Text('${r.providerName} · ${r.modelId}'),
              subtitle: Text('${r.message} · '
                  '${(r.elapsed.inMilliseconds / 1000).toStringAsFixed(1)} s'),
            ),
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('Only a short test message was sent. No document '
                  'text left the phone.', style: TextStyle(fontSize: 12)),
            ),
          ],
        )),
        actions: [TextButton(onPressed: () => Navigator.pop(dialogContext),
            child: const Text('OK'))],
      ));
  }

  Future<void> _saveModels(String providerId, List<String> models) async {
    final prefs = await SharedPreferences.getInstance();
    if (models.isEmpty) return;
    await prefs.setString('ai_model_$providerId', models.first);
    await prefs.setStringList(AiTextGateway.extraModelsKey(providerId),
        models.skip(1).toList());
    await _refresh();
  }

  Future<String?> _askModelId() async {
    var draft = '';
    return showDialog<String>(context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add model'),
        content: TextField(
          key: const Key('ai-add-model-field'),
          autofocus: true,
          autocorrect: false,
          decoration: const InputDecoration(
            labelText: 'Model ID',
            hintText: 'e.g. meta-llama/llama-3.3-70b-instruct:free'),
          onChanged: (text) => draft = text,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel')),
          FilledButton(key: const Key('ai-add-model-save'),
            onPressed: () => Navigator.pop(dialogContext, draft.trim()),
            child: const Text('Add')),
        ],
      ));
  }

  Future<List<String>?> _pickFreeModels(List<String> current) async {
    List<String> free;
    try {
      free = await (widget.loadFreeModels ??
          AiTextGateway.fetchOpenRouterFreeModels)();
    } catch (error) {
      _notice(error is AiTextException ? error.message
          : 'Could not load the OpenRouter model list.');
      return null;
    }
    if (!mounted) return null;
    final chosen = <String>{};
    return showDialog<List<String>>(context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text('Free OpenRouter models (${free.length})'),
          content: SizedBox(width: double.maxFinite, height: 380,
            child: free.isEmpty
                ? const Center(child: Text('No free models listed right now.'))
                : ListView(children: [
                    for (final id in free) CheckboxListTile(
                      dense: true,
                      value: current.contains(id) || chosen.contains(id),
                      onChanged: current.contains(id) ? null : (v) =>
                          setLocal(() => v == true
                              ? chosen.add(id) : chosen.remove(id)),
                      title: Text(id, style: const TextStyle(fontSize: 13)),
                    ),
                  ])),
          actions: [
            TextButton(key: const Key('ai-select-all-free'),
              onPressed: () => setLocal(() {
                final rest = free.where((id) => !current.contains(id));
                if (chosen.length == rest.length) {
                  chosen.clear();
                } else {
                  chosen.addAll(rest);
                }
              }),
              child: const Text('Select all')),
            TextButton(onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel')),
            FilledButton(key: const Key('ai-add-free-models'),
              onPressed: () => Navigator.pop(dialogContext, chosen.toList()),
              child: Text('Add ${chosen.length}')),
          ],
        )));
  }

  /// Model lists for every provider that supports several models. Opens on
  /// the active provider, but OpenRouter (and its free models) can be
  /// filled in whichever provider is active, so auto-switch can use them.
  Future<void> _manageModels() async {
    final providers = AiProviderCatalog.multiModelProviders.toList()
      ..sort((a, b) => a == 'openrouter' ? -1 : b == 'openrouter' ? 1
          : a.compareTo(b));
    var selected = providers.contains(_activeId) ? _activeId! : 'openrouter';
    final prefs = await SharedPreferences.getInstance();
    var models = await AiTextGateway.modelsFor(selected, prefs: prefs);
    if (!mounted) return;
    await showModalBottomSheet<void>(context: context, isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setLocal) {
          Future<void> reload(String id) async {
            final next = await AiTextGateway.modelsFor(id, prefs: prefs);
            setLocal(() {
              selected = id;
              models = next;
            });
          }
          Future<void> update(List<String> next) async {
            await _saveModels(selected, next);
            await reload(selected);
          }
          final keySaved = _hasKeys[selected] == true;
          return SafeArea(child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Column(mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Models', style: TextStyle(
                  fontSize: 17, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, children: [
                for (final id in providers) ChoiceChip(
                  key: Key('ai-models-provider-$id'),
                  label: Text(AiProviderCatalog.byId(id)?.name
                      .replaceAll(' (Gemini)', '') ?? id),
                  selected: selected == id,
                  onSelected: (_) => reload(id),
                ),
              ]),
              const SizedBox(height: 6),
              Text(keySaved
                  ? 'The first model is used first. If it fails, the next one '
                    'is tried automatically, then your other providers.'
                  : 'Save an API key for this provider to use these models.',
                  style: TextStyle(fontSize: 12,
                      color: keySaved ? null : Colors.orange)),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 300),
                child: ListView(shrinkWrap: true, children: [
                  for (var i = 0; i < models.length; i++) ListTile(
                    key: Key('ai-model-row-${models[i]}'),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Text('${i + 1}.'),
                    title: Text(models[i]),
                    subtitle: i == 0 ? const Text('Main model') : null,
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      if (i > 0) IconButton(tooltip: 'Use first',
                        icon: const Icon(Icons.vertical_align_top),
                        onPressed: () => update([models[i],
                          for (var k = 0; k < models.length; k++)
                            if (k != i) models[k]])),
                      if (models.length > 1) IconButton(tooltip: 'Remove',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => update([
                          for (var k = 0; k < models.length; k++)
                            if (k != i) models[k]])),
                    ]),
                  ),
                ]),
              ),
              const SizedBox(height: 6),
              Wrap(spacing: 8, runSpacing: 4, children: [
                OutlinedButton.icon(
                  key: const Key('ai-add-model'),
                  onPressed: () async {
                    final model = await _askModelId();
                    if (model == null || model.isEmpty) return;
                    if (!RegExp(r'^[A-Za-z0-9._:/-]{2,110}$').hasMatch(model)) {
                      _notice('Invalid model ID.');
                      return;
                    }
                    if (!models.contains(model)) {
                      await update([...models, model]);
                    }
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('Add model')),
                if (selected == 'openrouter') OutlinedButton.icon(
                  key: const Key('ai-browse-free-models'),
                  onPressed: () async {
                    final picked = await _pickFreeModels(models);
                    if (picked == null || picked.isEmpty) return;
                    await update([...models, ...picked]);
                  },
                  icon: const Icon(Icons.travel_explore),
                  label: const Text('Browse free models')),
                if (selected != 'openrouter') OutlinedButton.icon(
                  key: const Key('ai-open-openrouter-models'),
                  onPressed: () => reload('openrouter'),
                  icon: const Icon(Icons.travel_explore),
                  label: const Text('Add OpenRouter free models')),
              ]),
            ]),
          ));
        }));
    await _refresh();
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
        onOpenKeyPage: () => _openKeyPage(provider),
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
                    Text('Connect your own API key for approved text and '
                      'document image recognition. Your credentials stay encrypted '
                      'on this device.', style: TextStyle(color: Color(0xFFE3F9F7))),
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
                onChanged: (_hasKeys[_activeId] ?? false) &&
                    AiProviderCatalog.textModels.containsKey(_activeId)
                    ? _changeEnabled : null,
              )),
              if (active != null &&
                  AiProviderCatalog.textModels.containsKey(active.id))
                Card(child: ListTile(
                  key: const Key('ai-model-tile'),
                  leading: const Icon(Icons.tune_outlined, color: dsTeal),
                  title: const Text('Text AI model'),
                  subtitle: Text(_modelId ?? 'Choose a model'),
                  trailing: const Icon(Icons.edit_outlined),
                  onTap: () => _editModel(),
                )),
              if (active != null &&
                  AiProviderCatalog.visionModels.containsKey(active.id))
                Card(child: ListTile(
                  key: const Key('ai-vision-model-tile'),
                  leading: const Icon(Icons.document_scanner_outlined,
                    color: dsTeal),
                  title: const Text('Word / Excel vision model'),
                  subtitle: Text(_visionModelId ?? 'Choose a vision model'),
                  trailing: const Icon(Icons.edit_outlined),
                  onTap: () => _editModel(vision: true),
                )),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 10, 4, 12),
                child: Text(
                  'Google AI Studio, Groq, OpenRouter and DeepAI support optional '
                  'AI proofreading in text review. Word/Excel may use an '
                  'image-capable model with your separate confirmation for '
                  'each conversion. On-device OCR stays available. '
                  'Other provider slots store keys only for now.',
                  style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
                ),
              ),
              Card(child: ExpansionTile(
                key: const Key('ai-api-key-hints'),
                leading: const Icon(Icons.help_outline, color: dsTeal),
                title: const Text('Where to get an API key'),
                subtitle: const Text('Official links and quick instructions'),
                childrenPadding: const EdgeInsets.only(bottom: 10),
                children: [
                  _keyHelpRow('gemini',
                    'Sign in with Google → Create API key → Copy the key.'),
                  _keyHelpRow('groq',
                    'Sign in to GroqCloud → API Keys → Create API key.'),
                  _keyHelpRow('openrouter',
                    'Sign in → Keys → Create key. Check free model limits.'),
                  _keyHelpRow('deepai',
                    'Sign up → Dashboard → copy the API key shown there.'),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 5),
                    child: Text('For the other providers, use the official '
                      'Get API key link shown in each provider card. API '
                      'availability and charges depend on the provider.',
                      style: TextStyle(fontSize: 12)),
                  ),
                ],
              )),
              Card(child: ListTile(
                key: const Key('ai-import-key-file'),
                leading: const Icon(Icons.upload_file_outlined, color: dsTeal),
                title: const Text('Import API keys from a file'),
                subtitle: const Text('Pick a .txt, .env or .json file with all '
                    'your keys, for example gemini=AIza… on each line'),
                isThreeLine: true,
                trailing: const Icon(Icons.chevron_right),
                onTap: _importKeyFile,
              )),
              const SizedBox(height: 14),
              _heading('Providers with free-tier options'),
              for (final provider in AiProviderCatalog.providers.where((p) => p.freeTier))
                _providerTile(provider),
              const SizedBox(height: 18),
              _heading('More AI providers'),
              for (final provider in AiProviderCatalog.providers.where((p) => !p.freeTier))
                _providerTile(provider),
              const SizedBox(height: 18),
              _heading('API health & switching'),
              Card(child: ListTile(
                  key: const Key('ai-manage-models'),
                  leading: const Icon(Icons.view_list_outlined, color: dsTeal),
                  title: const Text('Models'),
                  subtitle: Text(active != null &&
                          AiProviderCatalog.multiModelProviders
                              .contains(active.id)
                      ? '${_models.length} ${active.name} model'
                        '${_models.length == 1 ? '' : 's'} · add OpenRouter '
                        'free models too'
                      : 'Gemini, Groq and OpenRouter models · add OpenRouter '
                        'free models'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _manageModels,
                )),
              Card(child: SwitchListTile.adaptive(
                key: const Key('ai-auto-switch'),
                secondary: const Icon(Icons.swap_horiz, color: dsTeal),
                title: const Text('Auto-switch if an API fails'),
                subtitle: const Text('Try your other models and saved '
                    'providers automatically'),
                value: _autoSwitch,
                onChanged: _setAutoSwitch,
              )),
              Card(child: ListTile(
                key: const Key('ai-check-apis'),
                leading: _checking
                    ? const SizedBox(width: 24, height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2.5))
                    : const Icon(Icons.network_check, color: dsTeal),
                title: const Text('Check APIs'),
                subtitle: const Text('Test which saved API keys and models '
                    'are working now'),
                onTap: _checking ? null : _checkApis,
              )),
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

  Future<void> _importKeyFile() async {
    String? text;
    try {
      final picker = widget.pickKeyFile;
      text = picker != null
          ? await picker()
          : await const MethodChannel('doclens/methods')
              .invokeMethod<String>('pickTextFile');
    } on PlatformException catch (error) {
      _notice(error.message ?? 'Could not read that file.');
      return;
    } catch (_) {
      _notice('Could not open the file picker.');
      return;
    }
    if (text == null || !mounted) return;
    if (text.length > AiKeyFileParser.maxBytes) {
      _notice('This file is too large for an API key list.');
      return;
    }
    final contents = AiKeyFileParser.parse(text);
    final ready = <ImportedAiKey>[];
    final problems = List<String>.of(contents.problems);
    for (final key in contents.keys) {
      final provider = AiProviderCatalog.byId(key.providerId)!;
      if (provider.needsAccountId && key.accountId == null &&
          !await _vault.hasAccountId(provider.id)) {
        problems.add('${provider.name}: add CLOUDFLARE_ACCOUNT_ID=… to the '
            'file as well.');
        continue;
      }
      ready.add(key);
    }
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('ai-import-preview'),
        title: Text(ready.isEmpty ? 'No usable API keys found'
            : 'Save ${ready.length} API key${ready.length == 1 ? '' : 's'}?'),
        content: SingleChildScrollView(child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final key in ready) Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                const Icon(Icons.key_outlined, color: dsTeal, size: 20),
                const SizedBox(width: 10),
                Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(AiProviderCatalog.byId(key.providerId)!.name,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text('${key.masked}'
                      '${(_hasKeys[key.providerId] ?? false) ? ' · replaces saved key' : ''}'
                      '${key.accountId != null ? ' · with account ID' : ''}',
                      style: const TextStyle(fontSize: 12)),
                ])),
              ]),
            ),
            if (ready.isEmpty) const Text('Write one key per line, for '
                'example:\n\ngemini=AIza...\ngroq=gsk_...\n'
                'openrouter=sk-or-...\nOPENAI_API_KEY=sk-proj-...'),
            if (problems.isNotEmpty) ...[
              const SizedBox(height: 10),
              const Text('Skipped:', style: TextStyle(
                  fontWeight: FontWeight.w600)),
              for (final problem in problems.take(12)) Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('• $problem', style: const TextStyle(fontSize: 12)),
              ),
              if (problems.length > 12) Text('• and ${problems.length - 12} '
                  'more', style: const TextStyle(fontSize: 12)),
            ],
          ],
        )),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
              child: Text(ready.isEmpty ? 'Close' : 'Cancel')),
          if (ready.isNotEmpty) FilledButton(
            key: const Key('ai-import-save'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save securely')),
        ],
      ),
    );
    if (confirmed != true) return;
    var saved = 0;
    for (final key in ready) {
      try {
        await _vault.saveKey(key.providerId, key.key, accountId: key.accountId);
        saved++;
      } catch (_) {
        // Keep importing the others; the count below reports the result.
      }
    }
    // With no usable provider chosen yet, pick the first imported one that
    // has AI features. AI Mode itself stays off until the user turns it on.
    try {
      final prefs = await SharedPreferences.getInstance();
      final current = prefs.getString(_providerPreference);
      final currentUsable = current != null &&
          await _vault.hasKey(current) &&
          AiProviderCatalog.textModels.containsKey(current);
      if (!currentUsable) {
        for (final key in ready) {
          if (AiProviderCatalog.textModels.containsKey(key.providerId)) {
            await prefs.setString(_providerPreference, key.providerId);
            break;
          }
        }
      }
    } catch (_) {}
    await _refresh();
    _notice(saved == ready.length
        ? '$saved API key${saved == 1 ? '' : 's'} saved securely. For safety, '
            'delete the key file from your phone.'
        : 'Saved $saved of ${ready.length} keys. Some could not be stored.');
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
            subtitle: Text('${provider.subtitle}\n${saved ? 'Key saved securely' : 'API key not added'}'
                '${AiProviderCatalog.textModels.containsKey(provider.id) ? ' · Text AI supported' : ' · Setup only'}',
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
          Padding(
            padding: const EdgeInsets.only(left: 64, right: 10),
            child: Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                key: Key('ai-get-key-${provider.id}'),
                onPressed: () => _openKeyPage(provider),
                icon: const Icon(Icons.open_in_new, size: 17),
                label: const Text('Get API key'),
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
    required this.onOpenKeyPage,
  });

  final AiProvider provider;
  final AiCredentialStore vault;
  final bool hasSavedKey;
  final Future<void> Function() onOpenKeyPage;

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
          FilledButton.tonalIcon(
            key: const Key('ai-open-key-website'),
            onPressed: widget.onOpenKeyPage,
            icon: const Icon(Icons.open_in_new),
            label: const Text('Open official API key website'),
          ),
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: widget.provider.keyPage));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('API key website link copied.')),
                );
              }
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
