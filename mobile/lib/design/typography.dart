import 'package:flutter/material.dart';

import 'tokens.dart';

/// The KOLO type system.
///
/// One family — Inter — across the whole product, because a financial app with
/// two typefaces reads as two products. Inter was chosen over a system font for
/// three concrete reasons: its digits are unambiguous at small sizes, it has a
/// true tabular-figure feature (so columns of naira amounts line up), and its
/// letterforms stay legible at the 11–13px used for metadata.
///
/// Two distinct scales exist here:
///   * [build] — the UI scale for text, labels and titles.
///   * [money] — the numeric scale, always tabular, with tighter tracking at
///     large sizes so a six-figure balance reads as one object.
class KoloType {
  KoloType._();

  static const String family = 'Inter';

  /// The weight ramp actually bundled. Anything outside this list will be
  /// synthesised by the engine and look slightly wrong.
  static const Map<int, FontWeight> weights = {
    400: FontWeight.w400,
    500: FontWeight.w500,
    600: FontWeight.w600,
    700: FontWeight.w700,
    800: FontWeight.w800,
  };

  static TextTheme build(TextTheme base, KoloColors colors) {
    TextStyle s({
      required double size,
      required FontWeight weight,
      required Color color,
      double height = 1.3,
      double tracking = 0,
    }) =>
        TextStyle(
          fontFamily: family,
          fontSize: size,
          fontWeight: weight,
          color: color,
          height: height,
          letterSpacing: tracking,
        );

    return TextTheme(
      // Display: reserved for the one number a screen is about.
      displayLarge: s(size: 44, weight: FontWeight.w700, color: colors.text, height: 1.05, tracking: -1.4),
      displayMedium: s(size: 36, weight: FontWeight.w700, color: colors.text, height: 1.08, tracking: -1.0),
      displaySmall: s(size: 30, weight: FontWeight.w700, color: colors.text, height: 1.12, tracking: -0.7),

      // Headlines: screen titles.
      headlineLarge: s(size: 26, weight: FontWeight.w700, color: colors.text, height: 1.2, tracking: -0.5),
      headlineMedium: s(size: 22, weight: FontWeight.w700, color: colors.text, height: 1.22, tracking: -0.35),
      headlineSmall: s(size: 19, weight: FontWeight.w600, color: colors.text, height: 1.25, tracking: -0.2),

      // Titles: card and section headers.
      titleLarge: s(size: 17, weight: FontWeight.w600, color: colors.text, height: 1.3, tracking: -0.1),
      titleMedium: s(size: 15, weight: FontWeight.w600, color: colors.text, height: 1.35),
      titleSmall: s(size: 13.5, weight: FontWeight.w600, color: colors.text, height: 1.35),

      // Body: the reading scale.
      bodyLarge: s(size: 15.5, weight: FontWeight.w400, color: colors.text, height: 1.5),
      bodyMedium: s(size: 14, weight: FontWeight.w400, color: colors.text, height: 1.5),
      bodySmall: s(size: 12.5, weight: FontWeight.w400, color: colors.textSoft, height: 1.45),

      // Labels: buttons, chips, tab text.
      labelLarge: s(size: 14.5, weight: FontWeight.w600, color: colors.text, height: 1.2),
      labelMedium: s(size: 12.5, weight: FontWeight.w600, color: colors.text, height: 1.2, tracking: 0.1),
      labelSmall: s(size: 11, weight: FontWeight.w600, color: colors.textSoft, height: 1.2, tracking: 0.3),
    );
  }

  /// Eyebrow: the small uppercase label above a section.
  ///
  /// Used sparingly — it is a wayfinding device, not decoration. The open
  /// tracking is what makes 11px uppercase readable rather than cramped.
  static TextStyle eyebrow(KoloColors colors) => TextStyle(
        fontFamily: family,
        fontSize: 10.5,
        fontWeight: FontWeight.w700,
        color: colors.textFaint,
        letterSpacing: 1.1,
        height: 1.2,
      );

  /// A monetary figure.
  ///
  /// Always tabular so amounts stack vertically, always tight-tracked at size so
  /// the digits group into one readable quantity, and never condensed — a
  /// squeezed balance is a misread balance.
  static TextStyle money(
    KoloColors colors, {
    double size = 16,
    FontWeight weight = FontWeight.w600,
    Color? color,
  }) =>
      TextStyle(
        fontFamily: family,
        fontSize: size,
        fontWeight: weight,
        color: color ?? colors.text,
        height: 1.15,
        letterSpacing: size >= 28 ? -1.2 : (size >= 20 ? -0.5 : -0.1),
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  /// The currency symbol inside a money line, set smaller than the figure so
  /// the number itself carries the emphasis.
  static TextStyle currencyMark(KoloColors colors, {double size = 16, Color? color}) =>
      TextStyle(
        fontFamily: family,
        // 0.72, not 0.62. The naira sign carries two strokes through a barred N;
        // at 62% it collapses into a smudge beside a large figure.
        fontSize: size * 0.72,
        fontWeight: FontWeight.w700,
        color: color ?? colors.textSoft,
        height: 1.0,
        fontFeatures: const [FontFeature.tabularFigures()],
      );
}
