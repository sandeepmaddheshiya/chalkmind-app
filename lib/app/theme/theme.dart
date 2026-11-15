import 'package:flutter/material.dart';

class BoardTheme {
  // Precision Architect & Studio Colors (Non-synthetic, human-crafted)
  static const Color primary = Color(0xFF2563EB); // Prussian Blue
  static const Color primaryDark = Color(0xFF1D4ED8);
  static const Color accent = Color(0xFF475569); // Slate Grey
  static const Color success = Color(0xFF059669); // Classroom Chalk Emerald
  static const Color warning = Color(0xFFD97706); // Warm Amber
  static const Color error = Color(0xFFDC2626); // Instructor Crimson

  // Canvas Background Presets
  static const Color canvasLight = Color(0xFFFFFFFF);
  static const Color canvasWarm = Color(0xFFFBF9F5); // Warm Archival Paper
  static const Color canvasDark = Color(0xFF13151A); // Studio Obsidian
  static const Color canvasChalkboard = Color(
    0xFF182A22,
  ); // Traditional Chalkboard Green

  // Surfaces
  static const Color surfaceDark = Color(0xFF0F1115);
  static const Color surfaceLight = Color(0xFFF4F3F0);
  static const Color panelDark = Color(0xFF181B22);
  static const Color panelLight = Color(0xFFFFFFFF);

  static ThemeData lightTheme() {
    final base = ThemeData.light(useMaterial3: true);
    return base.copyWith(
      colorScheme: ColorScheme.fromSeed(
        seedColor: primary,
        brightness: Brightness.light,
        surface: panelLight,
      ),
      scaffoldBackgroundColor: surfaceLight,
      appBarTheme: const AppBarTheme(
        backgroundColor: panelLight,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: TextStyle(
          color: Color(0xFF0F172A),
          fontSize: 16,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
        iconTheme: IconThemeData(color: Color(0xFF334155), size: 20),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: panelLight,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Color(0xFFE2E0D9), width: 1),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: panelLight,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFFE2E0D9), width: 1),
        ),
        elevation: 4,
      ),
    );
  }

  static ThemeData darkTheme() {
    final base = ThemeData.dark(useMaterial3: true);
    return base.copyWith(
      colorScheme: ColorScheme.fromSeed(
        seedColor: primary,
        brightness: Brightness.dark,
        surface: panelDark,
      ),
      scaffoldBackgroundColor: surfaceDark,
      appBarTheme: const AppBarTheme(
        backgroundColor: panelDark,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: TextStyle(
          color: Color(0xFFF1F5F9),
          fontSize: 16,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
        iconTheme: IconThemeData(color: Color(0xFF94A3B8), size: 20),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: panelDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Color(0xFF262A34), width: 1),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: panelDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF262A34), width: 1),
        ),
        elevation: 4,
      ),
    );
  }
}
