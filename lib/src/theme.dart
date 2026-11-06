import 'package:flutter/material.dart';

const dsTeal = Color(0xFF00B69B);
const dsInk = Color(0xFF172127);
const dsMuted = Color(0xFF7B8991);
const dsPaper = Color(0xFFF6F8F9);

ThemeData buildDocTheme({required bool dark}) {
  final scheme = ColorScheme.fromSeed(
    seedColor: dsTeal,
    brightness: dark ? Brightness.dark : Brightness.light,
    primary: dsTeal,
    surface: dark ? const Color(0xFF141B20) : Colors.white,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: dark ? const Color(0xFF101519) : dsPaper,
    appBarTheme: AppBarTheme(
      backgroundColor: dark ? const Color(0xFF101519) : Colors.white,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
    ),
    cardTheme: CardThemeData(
      color: scheme.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: dsTeal,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
        shape: const StadiumBorder(),
      ),
    ),
  );
}
