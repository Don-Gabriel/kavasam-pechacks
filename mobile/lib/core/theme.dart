import 'package:flutter/material.dart';

abstract final class KavasamColors {
  static const ink = Color(0xFF152520);
  static const forest = Color(0xFF0D5C46);
  static const mint = Color(0xFFDDF4E9);
  static const cream = Color(0xFFFFFBF2);
  static const saffron = Color(0xFFFFB547);
  static const danger = Color(0xFFB42318);
  static const dangerSoft = Color(0xFFFFE9E6);
}

abstract final class KavasamTheme {
  static ThemeData light({required bool paattiMode}) {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: KavasamColors.forest,
        primary: KavasamColors.forest,
        secondary: KavasamColors.saffron,
        surface: KavasamColors.cream,
      ),
      scaffoldBackgroundColor: KavasamColors.cream,
      fontFamily: 'sans-serif',
    );
    return base.copyWith(
      textTheme: base.textTheme.apply(
        bodyColor: KavasamColors.ink,
        displayColor: KavasamColors.ink,
      ),
      cardTheme: const CardThemeData(
        color: Colors.white,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(24)),
          side: BorderSide(color: Color(0xFFE2E9E5)),
        ),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
          borderSide: BorderSide(color: Color(0xFFD8E2DD)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
          borderSide: BorderSide(color: Color(0xFFD8E2DD)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: Size.fromHeight(paattiMode ? 64 : 54),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: TextStyle(
            fontSize: paattiMode ? 19 : 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
