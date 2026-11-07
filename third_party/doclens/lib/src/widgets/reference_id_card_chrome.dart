import 'package:flutter/material.dart';

import '../models.dart';
import 'reference_scan_settings.dart';

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

    return AnimatedBuilder(
      animation: settings,
      builder: (context, _) => Material(
        color: Colors.black,
        child: Stack(fit: StackFit.expand, children: [
          Column(children: [
            SizedBox(height: headerHeight,
              child: Padding(padding: EdgeInsets.only(top: top),
                child: Row(children: [
                  IconButton(tooltip: 'Close card camera', onPressed: onClose,
                    icon: const Icon(Icons.close, color: Colors.white, size: 29)),
                  const Spacer(),
                  IconButton(tooltip: 'Flash', onPressed: onFlash,
                    icon: Icon(_flashIcon, color: Colors.white, size: 26)),
                  IconButton(tooltip: 'HD', onPressed: () =>
                      settings.togglePanel(ScanCameraPanel.hd),
                    icon: const Text('HD', style: TextStyle(color: Colors.white,
                      fontSize: 16, fontWeight: FontWeight.w900))),
                  IconButton(tooltip: 'Settings',
                    onPressed: () => settings.togglePanel(ScanCameraPanel.settings),
                    icon: const Icon(Icons.more_vert, color: Colors.white)),
                  const SizedBox(width: 6),
                ]),
              ),
            ),
            Expanded(child: Stack(fit: StackFit.expand, children: [
              ClipRect(child: preview),
              if (settings.grid) IgnorePointer(child: CustomPaint(
                painter: _CardGridPainter(),
              )),
              Center(child: LayoutBuilder(builder: (context, constraints) {
                final frameWidth = constraints.maxWidth * .88;
                final frameHeight = portraitGuide
                    ? (constraints.maxHeight * .92).clamp(100.0, 650.0).toDouble()
                    : frameWidth / 1.58;
                final width = portraitGuide
                    ? frameHeight * .70 : frameWidth;
                return Center(child: SizedBox(
                  width: width.clamp(80.0, frameWidth).toDouble(),
                  height: frameHeight,
                  child: const CustomPaint(painter: _CardCornersPainter()),
                ));
              })),
              Positioned(top: 21, left: 16, right: 16,
                child: Center(child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 9),
                  decoration: BoxDecoration(color: const Color(0xA512171B),
                    borderRadius: BorderRadius.circular(18)),
                  child: Text(portraitGuide
                    ? 'Rotate your device and fit the document into the borders'
                    : (side == 'General' ? 'Fit it into the borders' : side),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white,
                      fontSize: 14.5)),
                )),
              ),
            ])),
            SizedBox(height: footerHeight,
              child: Padding(padding: EdgeInsets.only(bottom: bottom),
                child: Column(children: [
                  Container(height: 4, width: 26, color: accent),
                  const SizedBox(height: 9),
                  Text(label, style: TextStyle(color: accent, fontSize: 16)),
                  Expanded(child: Row(children: [
                    Expanded(child: Center(child: IconButton(
                      tooltip: 'Back to ID Cards',
                      onPressed: onClose,
                      icon: const Icon(Icons.undo, size: 30, color: Colors.white),
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
                    Expanded(child: InkWell(onTap: onImportImages,
                      child: const Column(mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_photo_alternate_outlined,
                            size: 27, color: Colors.white),
                          SizedBox(height: 4),
                          Text('Import Images', style: TextStyle(
                            color: Colors.white, fontSize: 11.5)),
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
    );
  }

  Widget _optionsPanel(BuildContext context) {
    if (settings.panel == ScanCameraPanel.hd) {
      return Material(color: const Color(0xFF0E0E0E),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 310),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Padding(padding: EdgeInsets.all(12), child: Text('HD Resolution',
              style: TextStyle(color: Colors.white, fontSize: 16))),
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
                color: Colors.white, fontSize: 19)),
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

class _CardCornersPainter extends CustomPainter {
  const _CardCornersPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    const segment = 25.0;
    const radius = 8.0;
    path
      ..moveTo(0, segment)..lineTo(0, radius)
      ..quadraticBezierTo(0, 0, radius, 0)..lineTo(segment, 0)
      ..moveTo(size.width - segment, 0)..lineTo(size.width - radius, 0)
      ..quadraticBezierTo(size.width, 0, size.width, radius)
      ..lineTo(size.width, segment)
      ..moveTo(size.width, size.height - segment)
      ..lineTo(size.width, size.height - radius)
      ..quadraticBezierTo(size.width, size.height,
        size.width - radius, size.height)
      ..lineTo(size.width - segment, size.height)
      ..moveTo(segment, size.height)..lineTo(radius, size.height)
      ..quadraticBezierTo(0, size.height, 0, size.height - radius)
      ..lineTo(0, size.height - segment);
    canvas.drawPath(path, Paint()
      ..color = Colors.white
      ..strokeWidth = 3.5
      ..style = PaintingStyle.stroke);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
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
