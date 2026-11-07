import 'package:flutter/material.dart';

import '../models.dart';

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

    return ColoredBox(
      color: Colors.black,
      child: Column(children: [
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
                  tooltip: 'Image enhancement',
                  onPressed: () => _notice(
                    context,
                    'Image enhancement filters are available after capture.',
                  ),
                  icon: const Icon(Icons.auto_awesome, color: Colors.white, size: 27),
                ),
                const SizedBox(width: 13),
                InkWell(
                  onTap: () => _notice(context, 'High-quality document capture is enabled.'),
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
                PopupMenuButton<String>(
                  tooltip: 'More scanner options',
                  color: const Color(0xFF202529),
                  icon: const Icon(Icons.more_vert, color: Colors.white, size: 27),
                  onSelected: (choice) {
                    switch (choice) {
                      case 'images':
                        onImportImages?.call();
                        break;
                      case 'files':
                        onImportFiles?.call();
                        break;
                      case 'manual':
                        onManualScan?.call();
                        break;
                      case 'flash':
                        onFlash();
                        break;
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'images', child: Text('Import Images', style: TextStyle(color: Colors.white))),
                    PopupMenuItem(value: 'files', child: Text('Import Files', style: TextStyle(color: Colors.white))),
                    PopupMenuItem(value: 'manual', child: Text('Manual Scan', style: TextStyle(color: Colors.white))),
                    PopupMenuItem(value: 'flash', child: Text('Flash mode', style: TextStyle(color: Colors.white))),
                  ],
                ),
                const SizedBox(width: 7),
              ]),
            ),
          ),
        ),
        Expanded(
          child: Stack(key: const Key('reference-preview'), fit: StackFit.expand, children: [
            ClipRect(child: preview),
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
}
