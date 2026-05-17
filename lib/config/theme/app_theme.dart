import 'package:flutter/material.dart';

/// Paleta inspirada en el video: fondo casi negro, acento verde neón
/// `#1DD27D`, rojo de alerta para el SOS.
class AppTheme {
  static const Color accentGreen = Color(0xFF1DD27D);
  static const Color sosRed = Color(0xFFE24B4A);
  static const Color radarGrid = Color(0xFF1A4537);
  static const Color cardBg = Color(0xFF1A1A1C);
  static const Color scaffoldBg = Color(0xFF09090B);
  static const Color textMuted = Color(0xFF8B8B8E);

  static ThemeData dark() {
    final base = ThemeData.dark(useMaterial3: true);
    return base.copyWith(
      colorScheme: const ColorScheme.dark(
        primary: accentGreen,
        secondary: accentGreen,
        surface: cardBg,
        error: sosRed,
        onPrimary: Colors.black,
        onSurface: Colors.white,
      ),
      scaffoldBackgroundColor: scaffoldBg,
      cardTheme: CardThemeData(
        color: cardBg,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: scaffoldBg,
        elevation: 0,
        centerTitle: false,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accentGreen,
          foregroundColor: Colors.black,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: cardBg,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
      textTheme: base.textTheme.apply(
        bodyColor: Colors.white,
        displayColor: Colors.white,
      ),
    );
  }
}
