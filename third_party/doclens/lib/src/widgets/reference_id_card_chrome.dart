import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models.dart';
import 'reference_scan_settings.dart';
import 'scan_chrome_style.dart';

/// White-corner alignment guides used only for ID Card template capture.
/// The live contour detector continues running underneath these guides.
class ReferenceIdCardChrome extends StatelessWidget {
  const ReferenceIdCardChrome({
    super.key,
    required this.preview,
    required this.label,
    required this.side,
    required this.portraitGuide,
    required this.accent,
    required this.flashMode,
    required this.capturing,
    required this.settings,
    required this.onClose,
    required this.onFlash,
    required this.onCapture,
    this.onImportImages,
    this.onMoreSettings,
    this.pagesCaptured = 0,
    this.waitingForBack = false,
    this.onFinishBatch,
    this.cameraModes = const [],
  });

  final Widget preview;
  final String label;
  final String side;
  final bool portraitGuide;
  final Color accent;
  final FlashMode flashMode;
  final bool capturing;
  final ReferenceScanSettings settings;
  final List<ScanCameraMode> cameraModes;
  final VoidCallback onClose;
  final VoidCallback onFlash;
  final VoidCallback onCapture;
  final VoidCallback? onImportImages;
  final VoidCallback? onMoreSettings;
  final int pagesCaptured;
  /// A two-sided card requires the next Back shot before it can finish.
  final bool waitingForBack;
  final VoidCallback? onFinishBatch;

  IconData get _flashIcon => switch (flashMode) {
        FlashMode.off => Icons.flash_off,
        FlashMode.auto => Icons.flash_auto,
        FlashMode.on => Icons.flash_on,
        FlashMode.torch => Icons.highlight,
      };

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final top = media.padding.top;
    final bottom = media.padding.bottom;
    final headerHeight = (media.size.height * .127)
        .clamp(top + 56, 130.0).toDouble();
    final footerHeight = (media.size.height * .245)
        .clamp(165.0, 260.0).toDouble();

    return ScanChromeStyle.clampText(context, AnimatedBuilder(
      animation: settings,
      builder: (context, _) => Material(
        color: Colors.black,
        child: Stack(fit: StackFit.expand, children: [
          Column(children: [
            SizedBox(height: headerHeight,
              child: Padding(padding: EdgeInsets.only(top: top),
                child: Row(children: [
                  IconButton(tooltip: 'Close card camera', onPressed: onClose,
                    icon: const Icon(Icons.close, color: Colors.white,
                        size: ScanChromeStyle.closeIcon)),
                  const Spacer(),
                  IconButton(tooltip: 'Flash', onPressed: onFlash,
                    icon: Icon(_flashIcon, color: Colors.white,
                        size: ScanChromeStyle.topIcon)),
                  const SizedBox(width: ScanChromeStyle.topIconGap),
                  IconButton(tooltip: 'HD', onPressed: () =>
                      settings.togglePanel(ScanCameraPanel.hd),
                    icon: const Icon(Icons.hd, color: Colors.white,
                        size: ScanChromeStyle.topIcon + 4)),
                  const SizedBox(width: ScanChromeStyle.topIconGap),
                  IconButton(tooltip: 'Settings',
                    onPressed: () => settings.togglePanel(ScanCameraPanel.settings),
                    icon: const Icon(Icons.more_vert, color: Colors.white,
                        size: ScanChromeStyle.topIcon)),
                  const SizedBox(width: 6),
                ]),
              ),
            ),
            Expanded(child: Stack(fit: StackFit.expand, children: [
              ClipRect(child: preview),
              if (settings.grid) IgnorePointer(child: CustomPaint(
                painter: _CardGridPainter(),
              )),
              // Card frame (reference screenshot 386535): the camera stays
              // clear inside rounded white corner brackets and is dimmed
              // around them.
              IgnorePointer(child: CustomPaint(
                key: const Key('card-frame'),
                painter: CardFramePainter(portraitGuide: portraitGuide),
              )),
              Positioned(top: 21, left: 16, right: 16,
                child: Center(child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 9),
                  decoration: BoxDecoration(color: const Color(0xA512171B),
                    borderRadius: BorderRadius.circular(18)),
                  child: Text(portraitGuide
                    ? 'Rotate your device and fit the document into the borders'
                    : (side == 'General' ? 'Front' : side),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white,
                      fontSize: ScanChromeStyle.hintFont)),
                )),
              ),
            ])),
            SizedBox(height: footerHeight,
              child: Padding(padding: EdgeInsets.only(bottom: bottom),
                child: Column(children: [
                  Container(height: 3, width: 26, color: accent),
                  const SizedBox(height: 8),
                  Text(label, style: TextStyle(color: accent,
                      fontSize: ScanChromeStyle.tabFont)),
                  Expanded(child: Row(children: [
                    Expanded(child: Center(child: IconButton(
                      tooltip: 'Back to ID Cards',
                      onPressed: onClose,
                      icon: const Icon(Icons.undo,
                          size: ScanChromeStyle.actionIcon, color: Colors.white),
                    ))),
                    SizedBox(width: 116,
                      child: Center(child: GestureDetector(
                        key: const Key('card-shutter'),
                        onTap: capturing ? null : onCapture,
                        child: Container(width: 80, height: 80,
                          decoration: BoxDecoration(shape: BoxShape.circle,
                            border: Border.all(color: accent, width: 4.5)),
                          padding: const EdgeInsets.all(7),
                          child: DecoratedBox(decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: capturing ? Colors.grey
                                : const Color(0xFFF4F4F4))),
                        ),
                      )),
                    ),
                    Expanded(child: InkWell(
                      key: const Key('card-right-action'),
                      onTap: waitingForBack ? null
                          : (onFinishBatch ?? onImportImages),
                      child: Column(mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(waitingForBack ? Icons.check_circle_outline
                              : pagesCaptured > 0 ? Icons.photo_library_outlined
                              : Icons.add_photo_alternate_outlined,
                            size: ScanChromeStyle.actionIcon,
                            color: waitingForBack ? accent : Colors.white),
                          const SizedBox(height: 4),
                          Text(waitingForBack ? '$pagesCaptured/2 captured'
                              : pagesCaptured > 0 ? '$pagesCaptured  Done'
                              : 'Import Images',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: ScanChromeStyle.actionFont)),
                        ],
                      ),
                    )),
                  ])),
                ]),
              ),
            ),
          ]),
          if (settings.panel != ScanCameraPanel.none)
            Positioned(top: headerHeight, left: 8, right: 8,
              child: _optionsPanel(context),
            ),
        ]),
      ),
    ));
  }

  Widget _optionsPanel(BuildContext context) {
    if (settings.panel == ScanCameraPanel.hd) {
      return Material(color: const Color(0xFF0E0E0E),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 310),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Padding(padding: EdgeInsets.all(12), child: Text('HD Resolution',
              style: TextStyle(color: Colors.white,
                  fontSize: ScanChromeStyle.panelTitleFont))),
            if (cameraModes.isEmpty)
              const Padding(padding: EdgeInsets.all(12),
                child: Text('Automatic (device default)',
                  style: TextStyle(color: Colors.white70)))
            else Flexible(child: ListView.builder(shrinkWrap: true,
              itemCount: cameraModes.length,
              itemBuilder: (context, index) {
                final mode = cameraModes[index];
                return ListTile(
                  dense: true,
                  title: Text(mode.label, style: const TextStyle(color: Colors.white)),
                  trailing: settings.resolution == mode.id
                    ? Icon(Icons.check, color: accent) : null,
                  onTap: () {
                    settings.selectResolution(mode.id);
                    settings.closePanel();
                  },
                );
              },
            )),
          ]),
        ),
      );
    }

    return Material(color: const Color(0xFF101010),
      borderRadius: BorderRadius.circular(15),
      child: ConstrainedBox(constraints: const BoxConstraints(maxHeight: 440),
        child: SingleChildScrollView(child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              const Text('Settings', style: TextStyle(
                color: Colors.white, fontSize: ScanChromeStyle.panelTitleFont,
                fontWeight: FontWeight.w600)),
              const Spacer(),
              IconButton(onPressed: settings.closePanel,
                icon: const Icon(Icons.close, color: Colors.white)),
            ]),
            for (final item in const [
              ('Auto Capture', 'autoCapture'), ('Grid', 'grid'),
              ('Sound', 'sound'), ('Spirit Level', 'spiritLevel'),
              ('Auto Crop', 'autoCrop'),
            ])
              SwitchListTile(
                dense: true,
                title: Text(item.$1,
                  style: const TextStyle(color: Colors.white)),
                value: settings.flag(item.$2),
                onChanged: (v) => settings.setFlag(item.$2, v),
              ),
            TextButton(onPressed: () {
              settings.closePanel();
              onMoreSettings?.call();
            }, child: Text('More Settings', style: TextStyle(color: accent))),
          ]),
        )),
      ),
    );
  }
}

/// Where the card frame sits inside the camera area: 88 % of the width at
/// the ID-1 card ratio (1.58), or a tall passport/certificate frame.
Rect cardFrameRect(Size area, {bool portraitGuide = false}) {
  final frameWidth = area.width * .88;
  final frameHeight = portraitGuide
      ? (area.height * .92).clamp(100.0, 650.0).toDouble()
      : frameWidth / 1.58;
  final width = (portraitGuide ? frameHeight * .70 : frameWidth)
      .clamp(80.0, frameWidth).toDouble();
  final height = math.min(frameHeight, area.height * .96);
  return Rect.fromCenter(center: area.center(Offset.zero),
      width: width, height: height);
}

/// Dims the camera around the card frame and draws its rounded corners.
class CardFramePainter extends CustomPainter {
  const CardFramePainter({this.portraitGuide = false});

  final bool portraitGuide;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = cardFrameRect(size, portraitGuide: portraitGuide);
    const radius = 12.0;
    final frame = RRect.fromRectAndRadius(rect, const Radius.circular(radius));
    canvas.drawPath(
      Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(Offset.zero & size)
        ..addRRect(frame),
      Paint()..color = const Color(0x8C000000),
    );
    final segment = math.min(rect.width, rect.height) * .12 + 6;
    final l = rect.left, t = rect.top, r = rect.right, b = rect.bottom;
    final path = Path()
      ..moveTo(l, t + segment)..lineTo(l, t + radius)
      ..quadraticBezierTo(l, t, l + radius, t)..lineTo(l + segment, t)
      ..moveTo(r - segment, t)..lineTo(r - radius, t)
      ..quadraticBezierTo(r, t, r, t + radius)..lineTo(r, t + segment)
      ..moveTo(r, b - segment)..lineTo(r, b - radius)
      ..quadraticBezierTo(r, b, r - radius, b)..lineTo(r - segment, b)
      ..moveTo(l + segment, b)..lineTo(l + radius, b)
      ..quadraticBezierTo(l, b, l, b - radius)..lineTo(l, b - segment);
    canvas.drawPath(path, Paint()
      ..color = Colors.white
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke);
  }

  @override
  bool shouldRepaint(covariant CardFramePainter oldDelegate) =>
      oldDelegate.portraitGuide != portraitGuide;
}

class _CardGridPainter extends CustomPainter {
  const _CardGridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white38..strokeWidth = .6;
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
