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
      // The scale below is generated from the design system's CSS, step for step:
      // a size here that is not in design/m.css is a size the design never drew.
      displayLarge: s(size: 40, weight: FontWeight.w700, color: colors.text, height: 1.0, tracking: -1.28),
      displayMedium: s(size: 32, weight: FontWeight.w700, color: colors.text, height: 1.08, tracking: -1.02),
      displaySmall: s(size: 30, weight: FontWeight.w700, color: colors.text, height: 1.05, tracking: -0.9),

      // Headlines: screen titles.
      headlineLarge: s(size: 24, weight: FontWeight.w700, color: colors.text, height: 1.15, tracking: -0.6),
      headlineMedium: s(size: 22, weight: FontWeight.w700, color: colors.text, height: 1.2, tracking: -0.53),
      headlineSmall: s(size: 19, weight: FontWeight.w700, color: colors.text, height: 1.2, tracking: -0.38),

      // Titles: card and section headers.
      titleLarge: s(size: 15.5, weight: FontWeight.w600, color: colors.text, height: 1.3, tracking: -0.19),
      titleMedium: s(size: 14.5, weight: FontWeight.w600, color: colors.text, height: 1.3, tracking: -0.12),
      titleSmall: s(size: 14, weight: FontWeight.w600, color: colors.text, height: 1.3, tracking: -0.11),

      // Body: the reading scale.
      bodyLarge: s(size: 14.5, weight: FontWeight.w400, color: colors.text, height: 1.5),
      bodyMedium: s(size: 13, weight: FontWeight.w400, color: colors.text, height: 1.45),
      bodySmall: s(size: 11.5, weight: FontWeight.w400, color: colors.textFaint, height: 1.45),

      // Labels: buttons, chips, tab text.
      labelLarge: s(size: 15, weight: FontWeight.w600, color: colors.text, height: 1.2, tracking: -0.12),
      labelMedium: s(size: 13, weight: FontWeight.w600, color: colors.text, height: 1.2),
      labelSmall: s(size: 11.5, weight: FontWeight.w600, color: colors.textSoft, height: 1.2, tracking: 0.06),
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
        letterSpacing: 1.365,
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
        height: size >= 28 ? 1.0 : 1.15,
        letterSpacing: size >= 28 ? 0 : (size >= 20 ? -0.53 : -0.29),
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

/// Turns a server token into something a person reads: `pending_approval` into
/// "Pending approval". Used wherever a raw status or category is displayed.
String koloHumanise(String raw) {
  if (raw.isEmpty) return '';
  final words = raw.replaceAll('_', ' ').trim();
  if (words.isEmpty) return '';
  return words[0].toUpperCase() + words.substring(1);
}
