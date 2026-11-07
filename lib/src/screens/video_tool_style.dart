import 'package:flutter/material.dart';

/// Shared colours and controls for the six user-supplied Tools reference videos.
/// These are original Flutter widgets; no third-party UI resources are used.
abstract final class VideoToolStyle {
  static const background = Color(0xFF1D1D20);
  static const header = Color(0xFF2A2A2D);
  static const panel = Color(0xFF303033);
  static const tile = Color(0xFF333336);
  static const muted = Color(0xFFAAA9AD);
  static const teal = Color(0xFF00BFA5);

  static ThemeData get dark => ThemeData.dark(useMaterial3: true).copyWith(
    scaffoldBackgroundColor: background,
    appBarTheme: const AppBarTheme(
      backgroundColor: header,
      foregroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
    ),
    colorScheme: const ColorScheme.dark(
      primary: teal, secondary: teal, surface: panel,
    ),
    cardTheme: const CardThemeData(
      color: tile,
      elevation: 0,
      margin: EdgeInsets.zero,
    ),
    dividerColor: const Color(0xFF3B3B3E),
  );

  static Widget wrapDark(Widget screen) => Theme(data: dark, child: screen);

  static ButtonStyle get tealButton => FilledButton.styleFrom(
    backgroundColor: teal,
    foregroundColor: Colors.white,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
    minimumSize: const Size.fromHeight(49),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
  );

  static ButtonStyle get greyButton => FilledButton.styleFrom(
    backgroundColor: const Color(0xFF48484C),
    foregroundColor: Colors.white,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
    minimumSize: const Size.fromHeight(49),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
  );
}

class VideoToolBottomBar extends StatelessWidget {
  const VideoToolBottomBar({
    super.key,
    required this.title,
    required this.onCancel,
    required this.onDone,
    this.busy = false,
  });

  final String title;
  final VoidCallback onCancel;
  final VoidCallback onDone;
  final bool busy;

  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(
      color: VideoToolStyle.header,
      borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
    ),
    child: SafeArea(top: false, child: SizedBox(height: 62, child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        IconButton(tooltip: 'Cancel', onPressed: busy ? null : onCancel,
          icon: const Icon(Icons.close, color: Colors.white, size: 27)),
        Text(title, style: const TextStyle(fontSize: 16, color: Colors.white)),
        IconButton(tooltip: 'Done', onPressed: busy ? null : onDone,
          icon: const Icon(Icons.check, color: Colors.white, size: 28)),
      ],
    ))),
  );
}
