import 'package:flutter/material.dart';

/// One set of sizes for every camera screen (Scan, ID Cards chooser and the
/// ID card camera), like CamScanner: compact, evenly spaced, and not blown
/// up by a large system font size, which pushed "Make it now" out of its
/// button and crowded the tabs on the user's phone.
abstract final class ScanChromeStyle {
  /// Camera chrome ignores system font scaling above this factor.
  static const maxTextScale = 1.0;

  static const closeIcon = 26.0;
  static const topIcon = 23.0;
  static const topIconGap = 6.0;
  static const hdFont = 14.5;

  static const modeFont = 13.0; // Single / Batch
  static const modeWidth = 74.0;
  static const tabFont = 14.5; // Scan / ID Cards
  static const tabGap = 44.0;
  static const actionIcon = 25.0; // Import Files / Import Images
  static const actionFont = 11.5;

  static const hintFont = 13.0;
  static const bodyFont = 12.0;
  static const chipFont = 12.5;
  static const buttonFont = 15.5;
  static const buttonHeight = 46.0;

  static const panelTitleFont = 17.0;
  static const settingFont = 14.0;
  static const settingValueFont = 12.0;

  /// Wrap a camera screen so its text keeps these sizes.
  static Widget clampText(BuildContext context, Widget child) =>
      MediaQuery.withClampedTextScaling(
        maxScaleFactor: maxTextScale, child: child);
}

/// The "Scan · ID Cards" switch under every camera screen.
class ScanModeTabs extends StatelessWidget {
  const ScanModeTabs({
    super.key,
    required this.idCardsSelected,
    required this.accent,
    this.onScan,
    this.onIdCards,
  });

  final bool idCardsSelected;
  final Color accent;
  final VoidCallback? onScan;
  final VoidCallback? onIdCards;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 42,
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          _tab('Scan', !idCardsSelected, onScan),
          const SizedBox(width: ScanChromeStyle.tabGap),
          _tab('ID Cards', idCardsSelected, onIdCards),
        ]),
      );

  Widget _tab(String name, bool selected, VoidCallback? onTap) => InkWell(
        key: Key('scan-mode-tab-$name'),
        onTap: selected ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Column(children: [
            Container(
              width: 26,
              height: 3,
              decoration: BoxDecoration(
                color: selected ? accent : Colors.transparent,
                borderRadius:
                    const BorderRadius.vertical(bottom: Radius.circular(3)),
              ),
            ),
            const SizedBox(height: 8),
            Text(name, maxLines: 1, style: TextStyle(
              color: selected ? accent : const Color(0xFFE0E0E0),
              fontSize: ScanChromeStyle.tabFont,
            )),
          ]),
        ),
      );
}

/// Flash icon for the current mode, shared by all camera screens.
IconData scanFlashIcon(bool on, {bool auto = false, bool torch = false}) =>
    torch ? Icons.highlight : auto ? Icons.flash_auto
        : on ? Icons.flash_on : Icons.flash_off;
