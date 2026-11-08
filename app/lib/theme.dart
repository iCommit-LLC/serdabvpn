import 'package:flutter/material.dart';

/// Warm black stone, sand strokes, one amber lantern. Nothing else.
abstract final class Palette {
  static const bg = Color(0xFF120F0C);
  static const surface = Color(0xFF1B1612);
  static const line = Color(0xFF2A231C);
  static const sand = Color(0xFFE8C48A);
  static const amber = Color(0xFFF2B65A);
  static const lamp = Color(0xFFFFD58A);
  static const text = Color(0xFFF3E9D8);
  static const muted = Color(0xFF8C7B66);
  static const danger = Color(0xFFD9735B);
}

ThemeData serdabTheme() {
  const scheme = ColorScheme.dark(
    primary: Palette.amber,
    onPrimary: Palette.bg,
    secondary: Palette.sand,
    surface: Palette.surface,
    onSurface: Palette.text,
    error: Palette.danger,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: Palette.bg,
    splashFactory: NoSplash.splashFactory,
    textTheme: const TextTheme(
      displayLarge: TextStyle(
        fontFamily: 'InstrumentSerif',
        fontSize: 44,
        color: Palette.text,
        height: 1.0,
      ),
      displayMedium: TextStyle(
        fontFamily: 'InstrumentSerif',
        fontSize: 32,
        color: Palette.text,
        height: 1.05,
      ),
      titleMedium: TextStyle(
        fontSize: 16,
        color: Palette.text,
        fontWeight: FontWeight.w500,
      ),
      bodyMedium: TextStyle(fontSize: 15, color: Palette.text, height: 1.4),
      bodySmall: TextStyle(fontSize: 13, color: Palette.muted, height: 1.4),
      labelLarge: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.2,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: Palette.sand,
        foregroundColor: Palette.bg,
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: Palette.sand,
        minimumSize: const Size.fromHeight(48),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Palette.surface,
      hintStyle: const TextStyle(color: Palette.muted),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Palette.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Palette.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Palette.sand),
      ),
    ),
    dialogTheme: const DialogThemeData(backgroundColor: Palette.surface),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: Palette.surface,
      contentTextStyle: TextStyle(color: Palette.text),
    ),
  );
}
