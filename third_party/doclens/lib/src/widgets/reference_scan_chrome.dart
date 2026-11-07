import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models.dart';
import 'reference_scan_settings.dart';

/// Camera-only chrome for DocScanner's Scan tab. The preview stays in its
/// own rectangular viewport; all controls live outside that viewport so a
/// detected quad cannot be painted over the shutter or the system navbar.
class ReferenceScanChrome extends StatelessWidget {
  const ReferenceScanChrome({
    super.key,
    required this.preview,
    required this.flashMode,
    required this.batchMode,
    required this.pageCount,
    required this.capturing,
    required this.accent,
    required this.onClose,
    required this.onFlash,
    required this.onCapture,
    required this.onBatchChanged,
    required this.onFinishBatch,
    required this.settings,
    this.cameraModes = const [],
    this.onMoreSettings,
    this.level = Offset.zero,
    this.onImportFiles,
    this.onImportImages,
    this.onIdCards,
    this.onManualScan,
  });

  final Widget preview;
  final FlashMode flashMode;
  final bool batchMode;
  final int pageCount;
  final bool capturing;
  final Color accent;
  final VoidCallback onClose;
  final VoidCallback onFlash;
  final VoidCallback onCapture;
  final ValueChanged<bool> onBatchChanged;
  final VoidCallback onFinishBatch;
  final ReferenceScanSettings settings;
  final List<ScanCameraMode> cameraModes;
  final VoidCallback? onMoreSettings;
  final Offset level;
  final VoidCallback? onImportFiles;
  final VoidCallback? onImportImages;
  final VoidCallback? onIdCards;
  final VoidCallback? onManualScan;

  IconData get _flashIcon => switch (flashMode) {
        FlashMode.off => Icons.flash_off,
        FlashMode.auto => Icons.flash_auto,
        FlashMode.on => Icons.flash_on,
        FlashMode.torch => Icons.highlight,
      };

  void _notice(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height;
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    final topInset = MediaQuery.viewPaddingOf(context).top;
    final headerHeight = (height * 0.127).clamp(topInset + 54, 128.0).toDouble();
    final footerHeight = (height * 0.254).clamp(174.0, 265.0).toDouble();

    return AnimatedBuilder(
      animation: settings,
      builder: (context, _) => ColoredBox(
      color: Colors.black,
      child: Stack(fit: StackFit.expand, children: [
        Column(children: [
        SizedBox(
          height: headerHeight,
          child: Padding(
            padding: EdgeInsets.only(top: topInset, bottom: 11),
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Row(children: [
                IconButton(
                  tooltip: 'Close scanner',
                  onPressed: onClose,
                  icon: const Icon(Icons.close, color: Colors.white, size: 31),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Flash',
                  onPressed: onFlash,
                  icon: Icon(_flashIcon, color: Colors.white, size: 26),
                ),
                const SizedBox(width: 13),
                IconButton(
                  tooltip: 'Effects',
                  onPressed: () => settings.togglePanel(ScanCameraPanel.effects),
                  icon: const Icon(Icons.auto_awesome, color: Colors.white, size: 27),
                ),
                const SizedBox(width: 13),
                InkWell(
                  onTap: () => settings.togglePanel(ScanCameraPanel.hd),
                  child: const SizedBox(
                    width: 43,
                    height: 45,
                    child: Center(
                      child: Text('HD', style: TextStyle(
                        color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900)),
                    ),
                  ),
                ),
                const SizedBox(width: 7),
                IconButton(
                  tooltip: 'Scanner Settings',
                  icon: const Icon(Icons.more_horiz, color: Colors.white, size: 27),
                  onPressed: () => settings.togglePanel(ScanCameraPanel.settings),
                ),
                const SizedBox(width: 7),
              ]),
            ),
          ),
        ),
        Expanded(
          child: Stack(key: const Key('reference-preview'), fit: StackFit.expand, children: [
            ClipRect(child: preview),
            if (settings.grid) const IgnorePointer(child: CustomPaint(
              painter: _ScanGridPainter(),
            )),
            if (settings.spiritLevel) IgnorePointer(child: Center(
              child: Transform.rotate(
                angle: -level.dx * math.pi / 180,
                child: Container(
                  width: 124, height: 27,
                  alignment: Alignment.center,
                  child: Stack(alignment: Alignment.center, children: [
                    Container(height: 2, color: Colors.white70),
                    Container(width: 6, height: 22, color: Colors.white70),
                    Transform.translate(
                      offset: Offset(level.dx * 1.5, level.dy * 1.5),
                      child: Container(
                        width: 16, height: 16,
                        decoration: BoxDecoration(
                          color: level.distance < 5 ? accent : Colors.orange,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ]),
                ),
              ),
            )),
            IgnorePointer(
              child: DecoratedBox(decoration: BoxDecoration(
                border: Border.all(color: accent.withValues(alpha: 0.78), width: 1.2),
              )),
            ),
            Positioned(
              bottom: 12,
              left: 0,
              right: 0,
              child: Center(child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xD9232529),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(3),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    _mode('Single', false),
                    _mode('Batch', true),
                  ]),
                ),
              )),
            ),
          ]),
        ),
        SizedBox(
          height: footerHeight,
          child: Padding(
            padding: EdgeInsets.only(bottom: bottomInset),
            child: Column(children: [
              SizedBox(
                height: 45,
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  _tab('Scan', true, null),
                  const SizedBox(width: 42),
                  _tab('ID Cards', false, onIdCards),
                ]),
              ),
              Expanded(child: Row(children: [
                Expanded(child: _importAction(
                  Icons.insert_drive_file_outlined, 'Import Files', onImportFiles)),
                SizedBox(
                  width: 112,
                  child: Center(child: Semantics(
                    button: true,
                    label: 'Capture document',
                    child: GestureDetector(
                      key: const Key('reference-shutter'),
                      onTap: capturing ? null : onCapture,
                      child: Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: Colors.black,
                          shape: BoxShape.circle,
                          border: Border.all(color: accent, width: 4.5),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(7),
                          child: DecoratedBox(decoration: BoxDecoration(
                            color: capturing ? const Color(0xFFAAAAAA) : const Color(0xFFF4F4F4),
                            shape: BoxShape.circle,
                          )),
                        ),
                      ),
                    ),
                  )),
                ),
                Expanded(child: batchMode && pageCount > 0
                  ? TextButton(
                      onPressed: onFinishBatch,
                      child: Text('Done ($pageCount)', style: TextStyle(color: accent)),
                    )
                  : _importAction(
                      Icons.add_photo_alternate_outlined, 'Import\nImages', onImportImages)),
              ])),
            ]),
          ),
        ),
        ]),
        if (settings.panel != ScanCameraPanel.none)
          Positioned(
            top: headerHeight,
            left: 0,
            right: 0,
            child: _activePanel(context, height - headerHeight - footerHeight),
          ),
      ]),
    ),
    );
  }

  Widget _mode(String label, bool isBatch) {
    final selected = batchMode == isBatch;
    return InkWell(
      borderRadius: BorderRadius.circular(23),
      onTap: selected ? null : () => onBatchChanged(isBatch),
      child: Container(
        width: 82,
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF777777) : Colors.transparent,
          borderRadius: BorderRadius.circular(23),
        ),
        child: Text(label, textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white, fontSize: 14)),
      ),
    );
  }

  Widget _tab(String name, bool selected, VoidCallback? onTap) => InkWell(
    onTap: onTap,
    child: Column(mainAxisAlignment: MainAxisAlignment.start, children: [
      Container(
        width: 28,
        height: 4,
        decoration: BoxDecoration(
          color: selected ? accent : Colors.transparent,
          borderRadius: const BorderRadius.vertical(bottom: Radius.circular(4)),
        ),
      ),
      const SizedBox(height: 7),
      Text(name, style: TextStyle(
        color: selected ? accent : const Color(0xFFE0E0E0), fontSize: 17,
      )),
    ]),
  );

  Widget _importAction(IconData icon, String label, VoidCallback? onTap) => InkWell(
    onTap: onTap,
    child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 29, color: Colors.white),
      const SizedBox(height: 4),
      Text(label, textAlign: TextAlign.center, style: const TextStyle(
        color: Colors.white, fontSize: 12.5, height: 1.15,
      )),
    ])),
  );

  Widget _activePanel(BuildContext context, double availableHeight) =>
      switch (settings.panel) {
        ScanCameraPanel.effects => _effectsPanel(context),
        ScanCameraPanel.hd => _hdPanel(availableHeight),
        ScanCameraPanel.settings => _settingsPanel(context, availableHeight),
        ScanCameraPanel.none => const SizedBox.shrink(),
      };

  Widget _effectsPanel(BuildContext context) => Container(
        color: const Color(0xFA000000),
        padding: const EdgeInsets.fromLTRB(4, 12, 4, 10),
        child: GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: ScanEffectPreset.values.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 6,
            childAspectRatio: .65,
            mainAxisSpacing: 4,
            crossAxisSpacing: 2,
          ),
          itemBuilder: (_, index) {
            final effect = ScanEffectPreset.values[index];
            final selected = settings.effect == effect;
            return InkWell(
              key: Key('scan-effect-${effect.name}'),
              onTap: () {
                settings.selectEffect(effect);
                if (effect == ScanEffectPreset.noWatermark ||
                    effect == ScanEffectPreset.noHandwriting) {
                  _notice(context, 'Experimental local cleanup; review the result before saving.');
                }
              },
              child: Column(children: [
                Container(
                  width: 43,
                  height: 43,
                  decoration: BoxDecoration(
                    color: selected ? const Color(0xFF214D49) : const Color(0xFF565656),
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(
                      color: selected ? accent : Colors.transparent,
                      width: 1.3,
                    ),
                  ),
                  child: Icon(_effectIcon(effect),
                    color: selected ? accent : Colors.white, size: 24),
                ),
                const SizedBox(height: 5),
                Text(effect.label, textAlign: TextAlign.center,
                  maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected ? accent : Colors.white,
                    fontSize: 10.5,
                    height: 1.1,
                  )),
              ]),
            );
          },
        ),
      );

  IconData _effectIcon(ScanEffectPreset preset) => switch (preset) {
        ScanEffectPreset.original => Icons.article_outlined,
        ScanEffectPreset.lighten => Icons.wb_sunny_outlined,
        ScanEffectPreset.enhance => Icons.landscape_outlined,
        ScanEffectPreset.magicPro => Icons.auto_awesome,
        ScanEffectPreset.noWatermark => Icons.water_drop_outlined,
        ScanEffectPreset.noShadow => Icons.blur_off,
        ScanEffectPreset.noHandwriting => Icons.gesture,
        ScanEffectPreset.blackWhite => Icons.contrast,
        ScanEffectPreset.eco => Icons.filter_b_and_w,
        ScanEffectPreset.grayscale => Icons.gradient,
        ScanEffectPreset.invert => Icons.invert_colors,
      };

  Widget _hdPanel(double availableHeight) {
    if (cameraModes.isEmpty) {
      return const ColoredBox(color: Colors.black,
        child: Padding(
          padding: EdgeInsets.all(18),
          child: Text('Camera resolution: Automatic (device default)',
            style: TextStyle(color: Colors.white)),
        ),
      );
    }
    final collapsed = !settings.allHdModes;
    final topFour = cameraModes.take(4).toList();
    return Container(
      color: Colors.black,
      height: collapsed ? 112 : availableHeight.clamp(180.0, 470.0).toDouble(),
      child: Column(children: [
        if (collapsed)
          Expanded(child: Row(children: [
            for (final mode in topFour)
              Expanded(child: InkWell(
                onTap: () => settings.selectResolution(mode.id),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 9),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: settings.resolution == mode.id
                        ? const Color(0xFF30383A) : Colors.transparent,
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text('${(mode.width * mode.height / 1000000).round()}M',
                      style: TextStyle(fontSize: 14,
                        color: settings.resolution == mode.id ? accent : Colors.white)),
                    const SizedBox(height: 4),
                    Text('(${mode.id})', style: const TextStyle(
                      color: Color(0xFFAAAAAA), fontSize: 9)),
                  ]),
                ),
              )),
          ]))
        else
          Expanded(child: ListView.separated(
            itemCount: cameraModes.length,
            separatorBuilder: (_, _) => const Divider(
              height: 1, color: Color(0xFF383838)),
            itemBuilder: (_, index) {
              final mode = cameraModes[index];
              final selected = settings.resolution == mode.id;
              return ListTile(
                dense: true,
                title: Text(mode.label, style: const TextStyle(color: Colors.white)),
                trailing: Icon(selected
                  ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                  color: selected ? accent : Colors.white, size: 21),
                onTap: () => settings.selectResolution(mode.id),
              );
            },
          )),
        TextButton(
          onPressed: () => settings.expandHd(collapsed),
          child: Text(collapsed ? 'List All Modes ⌄' : 'Hide ⌃',
            style: const TextStyle(color: Colors.white, fontSize: 13)),
        ),
      ]),
    );
  }

  Widget _settingsPanel(BuildContext context, double availableHeight) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      constraints: BoxConstraints(maxHeight: availableHeight.clamp(250.0, 525.0).toDouble()),
      decoration: BoxDecoration(
        color: const Color(0xFF050505),
        borderRadius: BorderRadius.circular(17),
      ),
      child: SingleChildScrollView(child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 9),
        child: Column(children: [
          Row(children: [
            const Icon(Icons.settings_outlined, color: Colors.white, size: 24),
            const SizedBox(width: 9),
            const Text('Settings', style: TextStyle(
              color: Colors.white, fontSize: 19, fontWeight: FontWeight.w600)),
            const Spacer(),
            IconButton(
              tooltip: 'Close Settings',
              onPressed: settings.closePanel,
              icon: const Icon(Icons.close, color: Colors.white),
            ),
          ]),
          _settingToggle('Auto Capture', 'autoCapture'),
          _orientationRow(),
          _settingToggle('Grid', 'grid'),
          _settingToggle('Sound', 'sound'),
          _settingToggle('Spirit Level', 'spiritLevel'),
          _settingToggle('Auto Crop', 'autoCrop'),
          const Divider(height: 9, color: Color(0xFF242424)),
          TextButton(
            onPressed: () {
              settings.closePanel();
              onMoreSettings?.call();
            },
            child: Text('More Settings', style: TextStyle(color: accent, fontSize: 14)),
          ),
        ]),
      )),
    );
  }

  Widget _settingToggle(String label, String key) => SizedBox(
        height: 57,
        child: Row(children: [
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(label, style: const TextStyle(color: Colors.white, fontSize: 14)),
              const SizedBox(height: 3),
              Text(settings.flag(key) ? 'On' : 'Off',
                style: TextStyle(color: accent, fontSize: 13)),
            ],
          )),
          Switch(
            value: settings.flag(key),
            onChanged: (value) => settings.setFlag(key, value),
          ),
        ]),
      );

  Widget _orientationRow() => SizedBox(
        height: 62,
        child: Row(children: [
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('Orientation', style: TextStyle(color: Colors.white, fontSize: 14)),
              const SizedBox(height: 3),
              Text(switch (settings.orientation) {
                ScanOrientationMode.auto => 'Auto',
                ScanOrientationMode.portrait => 'Vertical',
                ScanOrientationMode.landscape => 'Horizontal',
              }, style: TextStyle(color: accent, fontSize: 13)),
            ],
          )),
          for (final choice in ScanOrientationMode.values)
            IconButton(
              tooltip: choice.name,
              onPressed: () => settings.selectOrientation(choice),
              style: IconButton.styleFrom(
                backgroundColor: settings.orientation == choice
                    ? accent : Colors.transparent,
              ),
              icon: Icon(switch (choice) {
                ScanOrientationMode.auto => Icons.screen_rotation,
                ScanOrientationMode.portrait => Icons.stay_current_portrait,
                ScanOrientationMode.landscape => Icons.stay_current_landscape,
              }, color: Colors.white, size: 20),
            ),
        ]),
      );
}

class _ScanGridPainter extends CustomPainter {
  const _ScanGridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0x99FFFFFF)
      ..strokeWidth = .7;
    for (var i = 1; i < 3; i++) {
      final x = size.width * i / 3;
      final y = size.height * i / 3;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
}
