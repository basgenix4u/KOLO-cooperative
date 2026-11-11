import 'package:flutter/material.dart';

/// KOLO's visual language.
///
/// Warm rather than corporate: these are savings groups of friends and family,
/// not a bank. The palette leans on a deep indigo for trust and a warm amber for
/// money, because green-for-money reads as "profit" and this app is about
/// pooled savings, not gain.
class KoloColors {
  KoloColors._();

  static const Color ink = Color(0xFF14142B);
  static const Color inkSoft = Color(0xFF4E4B66);
  static const Color inkFaint = Color(0xFF8A87A0);
  static const Color cloud = Color(0xFFF7F6FB);
  static const Color white = Color(0xFFFFFFFF);

  static const Color indigo = Color(0xFF2D2A8C);
  static const Color indigoLight = Color(0xFF5B57D1);
  static const Color amber = Color(0xFFE8A33D);
  static const Color amberSoft = Color(0xFFFDF3E2);

  static const Color success = Color(0xFF1E8A5F);
  static const Color successSoft = Color(0xFFE6F4EE);
  static const Color danger = Color(0xFFC0392B);
  static const Color dangerSoft = Color(0xFFFBEAE8);
  static const Color warning = Color(0xFFB7791F);
  static const Color warningSoft = Color(0xFFFDF6E3);

  static const Color divider = Color(0xFFE8E6F0);
}

class KoloTheme {
  KoloTheme._();

  static ThemeData light() {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: KoloColors.cloud,
      colorScheme: ColorScheme.fromSeed(
        seedColor: KoloColors.indigo,
        primary: KoloColors.indigo,
        secondary: KoloColors.amber,
        surface: KoloColors.white,
        error: KoloColors.danger,
        brightness: Brightness.light,
      ),
    );

    return base.copyWith(
      textTheme: _textTheme(base.textTheme),
      appBarTheme: const AppBarTheme(
        backgroundColor: KoloColors.cloud,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        foregroundColor: KoloColors.ink,
        titleTextStyle: TextStyle(
          color: KoloColors.ink,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
        ),
      ),
      cardTheme: CardTheme(
        color: KoloColors.white,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: KoloColors.divider),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: KoloColors.indigo,
          foregroundColor: KoloColors.white,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: KoloColors.indigo,
          minimumSize: const Size.fromHeight(52),
          side: const BorderSide(color: KoloColors.divider),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: KoloColors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: KoloColors.divider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: KoloColors.divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: KoloColors.indigo, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: KoloColors.danger),
        ),
        hintStyle: const TextStyle(color: KoloColors.inkFaint),
      ),
      dividerTheme: const DividerThemeData(color: KoloColors.divider, thickness: 1, space: 1),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: KoloColors.ink,
        contentTextStyle: const TextStyle(color: KoloColors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: KoloColors.cloud,
        side: const BorderSide(color: KoloColors.divider),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: KoloColors.inkSoft),
      ),
    );
  }

  static TextTheme _textTheme(TextTheme base) {
    return base.copyWith(
      displaySmall: const TextStyle(
        fontSize: 32, fontWeight: FontWeight.w700, color: KoloColors.ink, letterSpacing: -0.6,
      ),
      headlineMedium: const TextStyle(
        fontSize: 24, fontWeight: FontWeight.w700, color: KoloColors.ink, letterSpacing: -0.4,
      ),
      titleLarge: const TextStyle(
        fontSize: 18, fontWeight: FontWeight.w700, color: KoloColors.ink, letterSpacing: -0.2,
      ),
      titleMedium: const TextStyle(
        fontSize: 16, fontWeight: FontWeight.w600, color: KoloColors.ink,
      ),
      bodyLarge: const TextStyle(fontSize: 16, color: KoloColors.ink, height: 1.45),
      bodyMedium: const TextStyle(fontSize: 14, color: KoloColors.inkSoft, height: 1.45),
      bodySmall: const TextStyle(fontSize: 12.5, color: KoloColors.inkFaint, height: 1.4),
      labelLarge: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: KoloColors.ink),
    );
  }

  /// Tabular figures for money: columns of amounts must line up, and a digit
  /// that changes width while a value animates looks like a glitch.
  static const TextStyle moneyLarge = TextStyle(
    fontSize: 30,
    fontWeight: FontWeight.w700,
    color: KoloColors.ink,
    letterSpacing: -0.8,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  static const TextStyle moneyMedium = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w700,
    color: KoloColors.ink,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  static const TextStyle moneySmall = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: KoloColors.inkSoft,
    fontFeatures: [FontFeature.tabularFigures()],
  );
}
