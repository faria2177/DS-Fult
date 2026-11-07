import 'dart:async';

import 'package:camera/camera.dart' as camera;
import 'package:doclens/doclens.dart';
import 'package:flutter/material.dart';

import '../storage/document_store.dart';
import '../services/scan_settings_store.dart';
import '../theme.dart';
import 'id_card_screen.dart';
import 'id_card_templates.dart';
import 'scan_more_settings_screen.dart';

/// The dedicated ID Cards carousel seen before the user taps "Make it now".
/// It owns a lightweight camera preview and releases it before the native
/// document camera starts, preventing two camera sessions from racing.
class IdCardTemplateScreen extends StatefulWidget {
  const IdCardTemplateScreen({super.key, required this.store});

  final DocumentStore store;

  @override
  State<IdCardTemplateScreen> createState() => _IdCardTemplateScreenState();
}

class _IdCardTemplateScreenState extends State<IdCardTemplateScreen>
    with WidgetsBindingObserver {
  IdCardTemplate _selected = IdCardTemplate.general;
  camera.CameraController? _camera;
  ReferenceScanSettings _settings = ReferenceScanSettings();
  List<ScanCameraMode> _cameraModes = const [];
  bool _launching = false;
  bool _flash = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_prepare());
  }

  Future<void> _prepare() async {
    final settings = await ScanSettingsStore.load();
    final modes = await ScanSettingsStore.availableModes();
    if (!mounted) {
      settings.dispose();
      return;
    }
    _settings.dispose();
    _settings = settings..addListener(_saveSettings);
    setState(() => _cameraModes = modes);
    await _startPreview();
  }

  void _saveSettings() => unawaited(ScanSettingsStore.save(_settings));

  Future<void> _startPreview() async {
    if (!mounted || _launching || _camera != null) return;
    try {
      final devices = await camera.availableCameras();
      if (devices.isEmpty || !mounted || _launching) return;
      final device = devices.firstWhere(
        (device) => device.lensDirection == camera.CameraLensDirection.back,
        orElse: () => devices.first,
      );
      final next = camera.CameraController(
        device, camera.ResolutionPreset.medium, enableAudio: false,
      );
      await next.initialize();
      if (!mounted || _launching) {
        await next.dispose();
        return;
      }
      await next.setFlashMode(camera.FlashMode.off);
      setState(() => _camera = next);
    } catch (_) {
      // A reference sample is still usable on tablets without a camera.
    }
  }

  Future<void> _stopPreview() async {
    final previous = _camera;
    if (mounted) setState(() => _camera = null);
    if (previous != null) await previous.dispose();
  }

  Future<void> _toggleFlash() async {
    final controller = _camera;
    if (controller == null) return;
    try {
      final enabled = !_flash;
      await controller.setFlashMode(
        enabled ? camera.FlashMode.torch : camera.FlashMode.off,
      );
      if (mounted) setState(() => _flash = enabled);
    } catch (_) { /* Some camera devices lack a torch. */ }
  }

  Future<void> _showHdModes() async {
    await showModalBottomSheet<void>(
      context: context, backgroundColor: const Color(0xFF101010),
      builder: (context) => SafeArea(child: SizedBox(
        height: 330,
        child: Column(children: [
          const Padding(padding: EdgeInsets.all(14), child: Text('HD Resolution',
            style: TextStyle(color: Colors.white, fontSize: 18))),
          Expanded(child: _cameraModes.isEmpty
            ? const Center(child: Text('Automatic (device default)',
                style: TextStyle(color: Colors.white70)))
            : ListView.builder(itemCount: _cameraModes.length,
                itemBuilder: (context, index) {
                  final mode = _cameraModes[index];
                  return ListTile(
                    title: Text(mode.label,
                      style: const TextStyle(color: Colors.white)),
                    trailing: _settings.resolution == mode.id
                      ? const Icon(Icons.check, color: dsTeal) : null,
                    onTap: () {
                      _settings.selectResolution(mode.id);
                      Navigator.pop(context);
                    },
                  );
                })),
        ]),
      )),
    );
  }

  Future<void> _showSettings() async {
    await showModalBottomSheet<void>(
      context: context, backgroundColor: const Color(0xFF101010),
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(child: AnimatedBuilder(
        animation: _settings,
        builder: (context, _) => ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
          children: [
            const Text('Settings', style: TextStyle(
              color: Colors.white, fontSize: 19, fontWeight: FontWeight.bold)),
            for (final item in const [
              ('Auto Capture', 'autoCapture'),
              ('Grid', 'grid'), ('Sound', 'sound'),
              ('Spirit Level', 'spiritLevel'), ('Auto Crop', 'autoCrop'),
            ])
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(item.$1, style: const TextStyle(color: Colors.white)),
                value: _settings.flag(item.$2),
                onChanged: (v) => _settings.setFlag(item.$2, v),
              ),
            TextButton(onPressed: () async {
              Navigator.pop(sheetContext);
              await _stopPreview();
              if (!mounted) return;
              await Navigator.push<void>(this.context, MaterialPageRoute(
                builder: (_) => ScanMoreSettingsScreen(settings: _settings),
              ));
              if (mounted) unawaited(_startPreview());
            }, child: const Text('More Settings',
                style: TextStyle(color: dsTeal))),
          ],
        ),
      )),
    );
  }

  Future<void> _makeItNow() async {
    if (_launching) return;
    setState(() => _launching = true);
    await _stopPreview();
    if (!mounted) return;
    try {
      await Navigator.push<void>(context, MaterialPageRoute(
        builder: (_) => IdCardScreen(
          store: widget.store,
          kind: _selected.documentKind,
          template: _selected,
          openCameraInitially: true,
        ),
      ));
    } finally {
      if (mounted) {
        setState(() => _launching = false);
        unawaited(_startPreview());
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_startPreview());
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      unawaited(_stopPreview());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    final cameraToDispose = _camera;
    if (cameraToDispose != null) unawaited(cameraToDispose.dispose());
    _settings.removeListener(_saveSettings);
    _settings.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IdCardTemplateChooserContent(
    selected: _selected,
    onSelect: (choice) => setState(() => _selected = choice),
    onClose: () => Navigator.pop(context),
    onFlash: _toggleFlash,
    onHd: _showHdModes,
    onSettings: _showSettings,
    onMakeItNow: _makeItNow,
    busy: _launching,
    preview: _camera != null && _camera!.value.isInitialized
        ? camera.CameraPreview(_camera!) : null,
  );
}

/// Pure UI extracted from the camera lifecycle to allow screenshot/widget tests.
class IdCardTemplateChooserContent extends StatelessWidget {
  const IdCardTemplateChooserContent({
    super.key,
    required this.selected,
    required this.onSelect,
    required this.onClose,
    required this.onFlash,
    required this.onHd,
    required this.onSettings,
    required this.onMakeItNow,
    this.preview,
    this.busy = false,
  });

  final IdCardTemplate selected;
  final ValueChanged<IdCardTemplate> onSelect;
  final VoidCallback onClose;
  final VoidCallback onFlash;
  final VoidCallback onHd;
  final VoidCallback onSettings;
  final VoidCallback onMakeItNow;
  final Widget? preview;
  final bool busy;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    body: SafeArea(child: Column(children: [
      SizedBox(height: 62, child: Row(children: [
        IconButton(tooltip: 'Close ID Cards', onPressed: onClose,
          icon: const Icon(Icons.close, color: Colors.white, size: 30)),
        const Spacer(),
        IconButton(tooltip: 'Flash', onPressed: onFlash,
          icon: const Icon(Icons.flash_off, color: Colors.white)),
        TextButton(onPressed: onHd, child: const Text('HD', style: TextStyle(
          color: Colors.white, fontWeight: FontWeight.w900, fontSize: 17))),
        IconButton(tooltip: 'Settings', onPressed: onSettings,
          icon: const Icon(Icons.more_vert, color: Colors.white)),
        const SizedBox(width: 8),
      ])),
      Expanded(child: LayoutBuilder(builder: (context, constraints) {
        final height = constraints.maxHeight;
        return Stack(fit: StackFit.expand, children: [
          preview == null ? const _CameraFallback() : ClipRect(
            child: FittedBox(fit: BoxFit.cover, child: SizedBox(
              width: 300, height: 560, child: preview,
            )),
          ),
          const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [Color(0x19000000), Color(0x00000000), Color(0x77090000)],
          ))),
          Positioned(top: height * .07, left: 0, right: 0,
            child: Center(child: SizedBox(
              height: (height * .47).clamp(110.0, 290.0).toDouble(),
              child: AspectRatio(aspectRatio: .72,
                child: _TemplateIllustration(template: selected)),
            )),
          ),
          Positioned(left: 14, right: 14, bottom: 12,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Align(alignment: Alignment.centerLeft, child: Text(
                'Create and share ID copies for various situations, including '
                'banking, administration, and more.  Learn more >',
                maxLines: 3,
                style: TextStyle(fontSize: 12.5, color: Colors.white,
                  height: 1.25),
              )),
              const SizedBox(height: 15),
              SizedBox(height: 48, child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: IdCardTemplate.values.length,
                separatorBuilder: (_, index) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final type = IdCardTemplate.values[index];
                  final active = selected == type;
                  return InkWell(
                    key: Key('id-template-${type.name}'),
                    onTap: () => onSelect(type),
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 61, maxWidth: 91),
                      padding: const EdgeInsets.symmetric(horizontal: 11),
                      decoration: BoxDecoration(
                        color: active ? const Color(0xFFF5F5F5)
                            : const Color(0xAB322B2B),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      alignment: Alignment.center,
                      child: Text(type.label, textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12.5,
                          color: active ? Colors.black : Colors.white)),
                    ),
                  );
                },
              )),
              const SizedBox(height: 19),
              SizedBox(width: double.infinity, height: 47,
                child: FilledButton(
                  key: const Key('id-make-it-now'),
                  onPressed: busy ? null : onMakeItNow,
                  style: FilledButton.styleFrom(backgroundColor: dsTeal,
                    foregroundColor: Colors.white,
                    shape: const StadiumBorder()),
                  child: Text(busy ? 'Opening camera…' : 'Make it now',
                    style: const TextStyle(fontSize: 19)),
                ),
              ),
            ]),
          ),
        ]);
      })),
      SizedBox(height: 42, child: Row(children: [
        _nav('Scan', false, onClose),
        _nav('Smart Erase', false, null),
        _nav('ID Cards', true, null),
        _nav('Question Set', false, null),
        _nav('Translate', false, null),
      ])),
      SizedBox(height: 120, child: Align(alignment: Alignment.topLeft,
        child: InkWell(onTap: onClose,
          child: const Padding(padding: EdgeInsets.fromLTRB(43, 27, 20, 5),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.apps, color: Colors.white, size: 29),
              Text('All Features', style: TextStyle(
                color: Colors.white, fontSize: 10)),
            ]),
          ),
        ),
      )),
    ])),
  );

  Widget _nav(String label, bool active, VoidCallback? action) => Expanded(
    child: InkWell(onTap: action,
      child: Column(children: [
        Container(width: 24, height: 3,
          color: active ? dsTeal : Colors.transparent),
        const SizedBox(height: 7),
        Text(label, textAlign: TextAlign.center, maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 10.5,
            color: active ? dsTeal : Colors.white70)),
      ]),
    ),
  );
}

class _CameraFallback extends StatelessWidget {
  const _CameraFallback();

  @override
  Widget build(BuildContext context) => const DecoratedBox(
    decoration: BoxDecoration(gradient: LinearGradient(
      begin: Alignment.topLeft, end: Alignment.bottomRight,
      colors: [Color(0xFF212B2B), Color(0xFF54221F), Color(0xFF230E15)],
    )),
  );
}

class _TemplateIllustration extends StatelessWidget {
  const _TemplateIllustration({required this.template});
  final IdCardTemplate template;

  @override
  Widget build(BuildContext context) => Container(
    key: Key('id-example-${template.name}'),
    padding: const EdgeInsets.all(9),
    decoration: BoxDecoration(color: Colors.white,
      borderRadius: BorderRadius.circular(2)),
    child: Stack(children: [
      const Positioned(top: 0, left: 0, child: DecoratedBox(
        decoration: BoxDecoration(color: Color(0xFFAAAAAA),
          borderRadius: BorderRadius.all(Radius.circular(3))),
        child: Padding(padding: EdgeInsets.fromLTRB(6, 2, 6, 2),
          child: Text('A4 paper example', style: TextStyle(
            color: Colors.white, fontSize: 9)),
        ),
      )),
      Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (template == IdCardTemplate.certificate) ...[
          const Icon(Icons.workspace_premium_outlined,
            color: Color(0xFFBAA06A), size: 60),
          const Text('CERTIFICATE', style: TextStyle(
            letterSpacing: 2, color: Color(0xFF575757),
            fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 15),
          _line(.75), _line(.55), _line(.65),
        ] else if (template == IdCardTemplate.passport) ...[
          Container(width: 105, height: 139,
            decoration: BoxDecoration(
              color: const Color(0xFF1B3953),
              borderRadius: BorderRadius.circular(6)),
            child: const Column(mainAxisAlignment: MainAxisAlignment.center,
              children: [Icon(Icons.public, color: Color(0xFFE6D59A), size: 43),
                SizedBox(height: 12), Text('PASSPORT',
                  style: TextStyle(color: Colors.white, fontSize: 11))]),
          ),
        ] else ...[
          _exampleCard(template, back: false),
          if (template == IdCardTemplate.idCard ||
              template == IdCardTemplate.driverLicense ||
              template == IdCardTemplate.bankCard) ...[
            const SizedBox(height: 12),
            _exampleCard(template, back: true),
          ],
        ],
      ])),
    ]),
  );

  Widget _exampleCard(IdCardTemplate template, {required bool back}) {
    final isBank = template == IdCardTemplate.bankCard ||
        template == IdCardTemplate.general;
    return Container(
      width: 119, height: 74,
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: isBank && !back
          ? [const Color(0xFF0745AF), const Color(0xFF081B65)]
          : [const Color(0xFFF0E6D2), const Color(0xFFC8D9E8)]),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: const Color(0x33000000)),
      ),
      child: Padding(padding: const EdgeInsets.all(7), child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(isBank ? 'WORLD CARD' : template.label.toUpperCase(),
            style: TextStyle(fontSize: 8, fontWeight: FontWeight.w700,
              color: isBank && !back ? Colors.white : const Color(0xFF3D4752))),
          const Spacer(),
          Row(children: [
            Icon(back ? Icons.qr_code_2 : Icons.person,
              size: 25, color: isBank && !back
                ? Colors.white : const Color(0xFF65778F)),
            const SizedBox(width: 5),
            Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center,
              children: [_line(.95), _line(.7), _line(.84)])),
          ]),
        ],
      )),
    );
  }

  Widget _line(double fraction) => Align(
    alignment: Alignment.centerLeft,
    child: FractionallySizedBox(widthFactor: fraction,
      child: Container(height: 3, margin: const EdgeInsets.symmetric(vertical: 3),
        decoration: BoxDecoration(color: const Color(0xFF919EAD),
          borderRadius: BorderRadius.circular(2)),
      ),
    ),
  );
}
