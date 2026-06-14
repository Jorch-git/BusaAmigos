import 'package:flutter/material.dart';

/// Paletas para tema oscuro y claro. El verde de acento `#1DD27D` se
/// mantiene en ambos como color de marca; cambian fondos y textos.
class AppTheme {
  // ---- Colores de marca (compartidos) ----
  static const Color accentGreen = Color(0xFF1DD27D);
  static const Color sosRed = Color(0xFFE24B4A);

  // ---- Tema OSCURO ----
  static const Color darkRadarGrid = Color(0xFF1A4537);
  static const Color darkCardBg = Color(0xFF1A1A1C);
  static const Color darkScaffoldBg = Color(0xFF09090B);
  static const Color darkTextMuted = Color(0xFF8B8B8E);

  // ---- Tema CLARO ----
  static const Color lightRadarGrid = Color(0xFFB8E6CE);
  static const Color lightCardBg = Color(0xFFF2F3F5);
  static const Color lightScaffoldBg = Color(0xFFFFFFFF);
  static const Color lightTextMuted = Color(0xFF6B6B70);

  // ---- Accesores dinámicos según brillo ----
  // Estos permiten que widgets que usaban AppTheme.cardBg sigan funcionando,
  // resolviendo el color correcto según el tema actual del contexto.
  static Color radarGridOf(BuildContext c) =>
      Theme.of(c).brightness == Brightness.dark ? darkRadarGrid : lightRadarGrid;
  static Color cardBgOf(BuildContext c) =>
      Theme.of(c).brightness == Brightness.dark ? darkCardBg : lightCardBg;
  static Color scaffoldBgOf(BuildContext c) =>
      Theme.of(c).brightness == Brightness.dark ? darkScaffoldBg : lightScaffoldBg;
  static Color textMutedOf(BuildContext c) =>
      Theme.of(c).brightness == Brightness.dark ? darkTextMuted : lightTextMuted;

  // ---- Compatibilidad hacia atrás ----
  // Muchos widgets existentes usan AppTheme.cardBg / .scaffoldBg / .textMuted /
  // .radarGrid como constantes. Para no romperlos, los dejamos apuntando a la
  // paleta OSCURA. Lo ideal a futuro es migrarlos a los accesores *Of(context),
  // pero así el código actual compila sin cambios masivos.
  static const Color radarGrid = darkRadarGrid;
  static const Color cardBg = darkCardBg;
  static const Color scaffoldBg = darkScaffoldBg;
  static const Color textMuted = darkTextMuted;

  // ====================================================================
  // TEMA OSCURO
  // ====================================================================
  static ThemeData dark() {
    final base = ThemeData.dark(useMaterial3: true);
    return base.copyWith(
      colorScheme: const ColorScheme.dark(
        primary: accentGreen,
        secondary: accentGreen,
        surface: darkCardBg,
        error: sosRed,
        onPrimary: Colors.black,
        onSurface: Colors.white,
      ),
      scaffoldBackgroundColor: darkScaffoldBg,
      cardTheme: CardThemeData(
        color: darkCardBg,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: darkScaffoldBg,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
      ),
      elevatedButtonTheme: _elevatedButtonTheme(),
      inputDecorationTheme: _inputTheme(darkCardBg),
      textTheme: base.textTheme.apply(
        bodyColor: Colors.white,
        displayColor: Colors.white,
      ),
    );
  }

  // ====================================================================
  // TEMA CLARO
  // ====================================================================
  static ThemeData light() {
    final base = ThemeData.light(useMaterial3: true);
    return base.copyWith(
      colorScheme: const ColorScheme.light(
        primary: accentGreen,
        secondary: accentGreen,
        surface: lightCardBg,
        error: sosRed,
        onPrimary: Colors.white,
        onSurface: Color(0xFF1A1A1C),
      ),
      scaffoldBackgroundColor: lightScaffoldBg,
      cardTheme: CardThemeData(
        color: lightCardBg,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: lightScaffoldBg,
        foregroundColor: Color(0xFF1A1A1C),
        elevation: 0,
        centerTitle: false,
      ),
      elevatedButtonTheme: _elevatedButtonTheme(),
      inputDecorationTheme: _inputTheme(lightCardBg),
      textTheme: base.textTheme.apply(
        bodyColor: const Color(0xFF1A1A1C),
        displayColor: const Color(0xFF1A1A1C),
      ),
    );
  }

  static ElevatedButtonThemeData _elevatedButtonTheme() {
    return ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: accentGreen,
        foregroundColor: Colors.black,
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
      ),
    );
  }

  static InputDecorationTheme _inputTheme(Color fill) {
    return InputDecorationTheme(
      filled: true,
      fillColor: fill,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
    );
  }
}
