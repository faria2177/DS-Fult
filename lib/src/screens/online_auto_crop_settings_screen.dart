import 'package:flutter/material.dart';
import '../services/online_auto_crop_service.dart';
import '../theme.dart';

/// Online processing must not silently send an ID or NID to a remote service.
/// Users approve one HTTPS endpoint explicitly and can revoke access here.
class OnlineAutoCropSettingsScreen extends StatefulWidget {
  const OnlineAutoCropSettingsScreen({super.key});
  @override
  State<OnlineAutoCropSettingsScreen> createState() =>
      _OnlineAutoCropSettingsScreenState();
}

class _OnlineAutoCropSettingsScreenState
    extends State<OnlineAutoCropSettingsScreen> {
  final _url = TextEditingController();
  final _secret = TextEditingController();
  bool _consent = false;
  bool _busy = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final config = await OnlineAutoCropConfig.load();
    if (!mounted) return;
    _url.text = config.endpoint;
    setState(() {
      _consent = config.consent;
      _busy = false;
    });
  }

  Future<void> _save() async {
    setState(() { _busy = true; _error = null; });
    try {
      await OnlineAutoCropConfig.save(
        endpoint: _url.text,
        consent: _consent,
        newSecret: _secret.text,
      );
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) setState(() {
        _error = error is FormatException
            ? error.message : 'Could not save online detector settings.';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _url.dispose();
    _secret.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF1B1B1F),
    appBar: AppBar(title: const Text('Online First Auto Crop'),
      backgroundColor: const Color(0xFF2A2A2E)),
    body: ListView(padding: const EdgeInsets.all(20), children: [
      const Text('Online AI detects the four outer corners first. '
        'If the server or network fails, DocScanner automatically uses '
        'the existing offline detector. Final cropping stays on-device.',
        style: TextStyle(color: Colors.white70)),
      const SizedBox(height: 20),
      TextField(controller: _url,
        enabled: !_busy,
        keyboardType: TextInputType.url,
        autocorrect: false,
        decoration: const InputDecoration(
          labelText: 'Private HTTPS detector endpoint',
          hintText: 'https://your-server.example/v1/detect',
          border: OutlineInputBorder())),
      const SizedBox(height: 14),
      TextField(controller: _secret,
        enabled: !_busy, obscureText: true,
        autocorrect: false,
        decoration: const InputDecoration(
          labelText: 'Detector access token',
          helperText: 'Leave blank to keep the previously saved token',
          border: OutlineInputBorder())),
      const SizedBox(height: 16),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        activeThumbColor: dsTeal,
        value: _consent,
        onChanged: _busy ? null : (value) =>
            setState(() => _consent = value),
        title: const Text('Allow online auto crop',
            style: TextStyle(fontWeight: FontWeight.w600)),
        subtitle: const Text('I understand that selected scans, '
          'including ID cards, are sent to the configured server '
          'for boundary detection. Revoke at any time.'),
      ),
      const SizedBox(height: 12),
      const Text('No cloud upload occurs unless this switch is enabled '
        'and a valid HTTPS endpoint and token are saved. The server '
        'must be operated under an appropriate privacy policy.',
        style: TextStyle(color: Colors.white70, fontSize: 12)),
      if (_error != null) ...[
        const SizedBox(height: 12),
        Text(_error!, style: const TextStyle(color: Colors.redAccent)),
      ],
      const SizedBox(height: 20),
      FilledButton(onPressed: _busy ? null : _save,
        child: const Text('Save settings')),
    ]),
  );
}
