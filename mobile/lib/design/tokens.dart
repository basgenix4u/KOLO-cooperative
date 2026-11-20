import 'package:flutter/material.dart';

/// KOLO design tokens: Ink & Citrus.
///
/// The whole interface derives from this file. Nothing in the app should carry
/// a raw `Color(0x...)`, a magic padding number or a hand-written TextStyle —
/// if a value is needed twice it belongs here, so the product cannot drift into
/// looking like several apps stitched together.
///
/// The four brand colours are authoritative and are the only hues allowed:
///   Midnight Ink  #101820  authority, navigation, dark ground
///   Electric Citrus #D5F45A  recognition, primary action, meaningful highlight
///   Stone         #E9E7DF  warmth, breathing room, light surface
///   Slate         #64717C  supporting text, icons, neutral structure
///
/// Everything else below is a *tint of those four*, not a new colour. Status
/// green/red/amber are the one exception: a cooperative savings product has to
/// signal "paid", "shortfall" and "blocked" unambiguously, and citrus cannot
/// carry a negative meaning on its own. They are deliberately desaturated so
/// they read as cousins of the palette rather than a competing scheme.
class KoloBrand {
  KoloBrand._();

  static const Color ink = Color(0xFF101820);
  static const Color citrus = Color(0xFFD5F45A);
  static const Color stone = Color(0xFFE9E7DF);
  static const Color slate = Color(0xFF64717C);

  // --- Ink tints, for building depth without inventing colours -------------
  /// One step up from pure ink, for raised surfaces in dark mode.
  static const Color inkRaised = Color(0xFF18222C);
  /// Two steps up, for borders and inset wells in dark mode.
  static const Color inkHigh = Color(0xFF223039);
  /// Ink at low alpha, used for hairlines on light surfaces.
  static const Color inkHairline = Color(0x14101820);

  // --- Stone / light tints -------------------------------------------------
  /// Slightly lifted from Stone, for cards sitting on a Stone ground.
  static const Color stoneLight = Color(0xFFF4F2EC);
  /// Stone pushed toward white, for input wells.
  static const Color stoneWash = Color(0xFFFBFAF6);

  // --- Citrus tints --------------------------------------------------------
  /// Citrus deepened enough to read as text on a light surface (5.9:1 on white).
  static const Color citrusInk = Color(0xFF5E7016);
  /// Citrus at low alpha, for selected states that must not shout.
  static const Color citrusWash = Color(0x33D5F45A);
  /// Citrus at very low alpha, for chart fills.
  static const Color citrusVeil = Color(0x1AD5F45A);

  // --- Semantic financial states -------------------------------------------
  /// Money received, contribution confirmed, cycle paid.
  static const Color settled = Color(0xFF1F7A55);
  static const Color settledWash = Color(0xFFE3F1EA);
  /// Money owed, awaiting payment, in review.
  static const Color pending = Color(0xFF9A6B12);
  static const Color pendingWash = Color(0xFFF7EFDC);
  /// Failed, shortfall, blocked, rejected.
  static const Color failed = Color(0xFFA83A32);
  static const Color failedWash = Color(0xFFF8E7E5);
}

/// The resolved palette for the one theme.
///
/// Screens read `context.colors`. There is no second palette and no appearance
/// switch: the design system has a single light theme, so a screen cannot drift
/// into an appearance the design never specified.
@immutable
class KoloColors extends ThemeExtension<KoloColors> {
  const KoloColors({
    required this.ground,
    required this.surface,
    required this.surfaceRaised,
    required this.surfaceSunken,
    required this.hairline,
    required this.text,
    required this.textSoft,
    required this.textFaint,
    required this.accent,
    required this.accentOn,
    required this.accentText,
    required this.accentWash,
    required this.navBackground,
    required this.navActive,
    required this.navInactive,
    required this.settled,
    required this.settledWash,
    required this.pending,
    required this.pendingWash,
    required this.failed,
    required this.failedWash,
    required this.scrim,
  });

  /// The page background. Stone-based in light, Ink-based in dark.
  final Color ground;
  /// Default panel: cards, sheets, list rows.
  final Color surface;
  /// One level up from [surface] — a card inside a card, or a selected row.
  final Color surfaceRaised;
  /// A recessed area: input wells, chart tracks, progress grooves.
  final Color surfaceSunken;
  /// The 1px separator. Deliberately near-invisible; structure comes from
  /// spacing first and lines second.
  final Color hairline;

  final Color text;
  final Color textSoft;
  final Color textFaint;

  /// Electric Citrus. Reserved for primary action, current selection and the
  /// one number a screen is about. If everything is citrus, nothing is.
  final Color accent;
  /// Foreground that sits on [accent]. Ink in both themes — citrus is light, so
  /// a white label on it is unreadable.
  final Color accentOn;
  /// Citrus that is safe as *text* on [ground]. The brand citrus is only 1.4:1
  /// against Stone, so labels use this deepened tone instead.
  final Color accentText;
  /// A restrained citrus field for selected chips and highlight rows.
  final Color accentWash;

  final Color navBackground;
  final Color navActive;
  final Color navInactive;

  final Color settled;
  final Color settledWash;
  final Color pending;
  final Color pendingWash;
  final Color failed;
  final Color failedWash;

  /// Behind modal sheets.
  final Color scrim;


  static const KoloColors light = KoloColors(
    ground: KoloBrand.stone,
    surface: KoloBrand.stoneLight,
    surfaceRaised: Color(0xFFFDFCF8),
    surfaceSunken: Color(0xFFDEDCD3),
    hairline: Color(0x1A101820),
    text: KoloBrand.ink,
    // Slate is the brand's supporting tone but sits at 4.47:1 on a Stone card,
    // just under AA. Deepened one step along the same hue to 5.19:1.
    textSoft: Color(0xFF5A6772),
    // Tertiary tone for eyebrows and metadata. The original 8B959C was only
    // 2.47:1 - unreadable in daylight. Now 4.66:1 on the page ground and 5.15:1
    // on a card.
    textFaint: Color(0xFF5E676E),
    accent: KoloBrand.citrus,
    accentOn: KoloBrand.ink,
    accentText: Color(0xFF55660F),
    accentWash: Color(0x59D5F45A),
    navBackground: Color(0xFFFDFCF8),
    navActive: KoloBrand.ink,
    navInactive: Color(0xFF97A0A6),
    settled: KoloBrand.settled,
    settledWash: KoloBrand.settledWash,
    pending: KoloBrand.pending,
    pendingWash: KoloBrand.pendingWash,
    failed: KoloBrand.failed,
    failedWash: KoloBrand.failedWash,
    scrim: Color(0x99101820),
  );

  static const KoloColors dark = KoloColors(
    ground: KoloBrand.ink,
    surface: KoloBrand.inkRaised,
    surfaceRaised: Color(0xFF1E2A34),
    surfaceSunken: Color(0xFF0A1017),
    hairline: Color(0x1FFFFFFF),
    text: Color(0xFFF2F5F3),
    textSoft: Color(0xFF9BA9B3),
    // 6B7A85 measured 4.05:1 against the raised surface - below AA for the
    // eyebrow and metadata copy it is used for. Lifted to 5.38:1 on a card.
    textFaint: Color(0xFF8A97A1),
    accent: KoloBrand.citrus,
    accentOn: KoloBrand.ink,
    // Brand citrus already holds 13:1 on Midnight Ink, so in dark mode the text
    // tone can be the full-strength brand colour.
    accentText: KoloBrand.citrus,
    accentWash: Color(0x1AD5F45A),
    navBackground: Color(0xFF0C1219),
    navActive: KoloBrand.citrus,
    navInactive: Color(0xFF5C6A75),
    settled: Color(0xFF57C496),
    settledWash: Color(0xFF163126),
    pending: Color(0xFFD8A94A),
    pendingWash: Color(0xFF2C2517),
    failed: Color(0xFFE0746A),
    failedWash: Color(0xFF321B19),
    scrim: Color(0xCC000000),
  );

  @override
  KoloColors copyWith({
    Color? ground,
    Color? surface,
    Color? surfaceRaised,
    Color? surfaceSunken,
    Color? hairline,
    Color? text,
    Color? textSoft,
    Color? textFaint,
    Color? accent,
    Color? accentOn,
    Color? accentText,
    Color? accentWash,
    Color? navBackground,
    Color? navActive,
    Color? navInactive,
    Color? settled,
    Color? settledWash,
    Color? pending,
    Color? pendingWash,
    Color? failed,
    Color? failedWash,
    Color? scrim,
  }) {
    return KoloColors(
      ground: ground ?? this.ground,
      surface: surface ?? this.surface,
      surfaceRaised: surfaceRaised ?? this.surfaceRaised,
      surfaceSunken: surfaceSunken ?? this.surfaceSunken,
      hairline: hairline ?? this.hairline,
      text: text ?? this.text,
      textSoft: textSoft ?? this.textSoft,
      textFaint: textFaint ?? this.textFaint,
      accent: accent ?? this.accent,
      accentOn: accentOn ?? this.accentOn,
      accentText: accentText ?? this.accentText,
      accentWash: accentWash ?? this.accentWash,
      navBackground: navBackground ?? this.navBackground,
      navActive: navActive ?? this.navActive,
      navInactive: navInactive ?? this.navInactive,
      settled: settled ?? this.settled,
      settledWash: settledWash ?? this.settledWash,
      pending: pending ?? this.pending,
      pendingWash: pendingWash ?? this.pendingWash,
      failed: failed ?? this.failed,
      failedWash: failedWash ?? this.failedWash,
      scrim: scrim ?? this.scrim,
    );
  }

  /// Theme transitions are short and linear on colour so switching appearance
  /// never flashes. 200 ms is long enough to read as deliberate, short enough
  /// that it never delays the member.
  @override
  KoloColors lerp(ThemeExtension<KoloColors>? other, double t) {
    if (other is! KoloColors) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return KoloColors(
      ground: c(ground, other.ground),
      surface: c(surface, other.surface),
      surfaceRaised: c(surfaceRaised, other.surfaceRaised),
      surfaceSunken: c(surfaceSunken, other.surfaceSunken),
      hairline: c(hairline, other.hairline),
      text: c(text, other.text),
      textSoft: c(textSoft, other.textSoft),
      textFaint: c(textFaint, other.textFaint),
      accent: c(accent, other.accent),
      accentOn: c(accentOn, other.accentOn),
      accentText: c(accentText, other.accentText),
      accentWash: c(accentWash, other.accentWash),
      navBackground: c(navBackground, other.navBackground),
      navActive: c(navActive, other.navActive),
      navInactive: c(navInactive, other.navInactive),
      settled: c(settled, other.settled),
      settledWash: c(settledWash, other.settledWash),
      pending: c(pending, other.pending),
      pendingWash: c(pendingWash, other.pendingWash),
      failed: c(failed, other.failed),
      failedWash: c(failedWash, other.failedWash),
      scrim: c(scrim, other.scrim),
    );
  }
}

/// Spacing scale, on a 4pt grid.
///
/// Named by intent rather than size so a change here re-tunes every screen at
/// once. The jump from 24 to 32 is the one real hierarchy break: inside a
/// section things sit 4–16 apart, between sections 32.
class KoloSpace {
  KoloSpace._();

  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double section = 32;
  static const double hero = 40;

  /// Horizontal page margin. 20 keeps text off the edge without wasting width
  /// on a 360dp phone.
  static const double page = 20;

  /// The largest comfortable content width. On tablets and the web build the
  /// content is centred rather than stretched into unreadable measure.
  static const double maxContent = 560;
}

/// Corner radii. Deliberately restrained: fintech trust comes from precision,
/// so 8–16 rather than pill shapes everywhere. Full rounds are reserved for
/// things that are genuinely circular (avatars, status dots).
class KoloRadius {
  KoloRadius._();

  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double full = 999;
}

/// Motion language.
///
/// Short, decelerating, never bouncy. Motion here explains where a thing came
/// from; it never performs.
class KoloMotion {
  KoloMotion._();

  /// Colour and small state changes.
  static const Duration fast = Duration(milliseconds: 140);
  /// Standard transitions: sheets, expansions, route pushes.
  static const Duration base = Duration(milliseconds: 220);
  /// Larger surface changes, balance reveals.
  static const Duration slow = Duration(milliseconds: 320);

  static const Curve enter = Curves.easeOutCubic;
  static const Curve exit = Curves.easeInCubic;
  static const Curve standard = Curves.easeInOutCubic;
}

/// Convenience accessors so screens read `context.colors` / `context.text`.
extension KoloThemeContext on BuildContext {
  KoloColors get colors =>
      Theme.of(this).extension<KoloColors>() ?? KoloColors.light;

  TextTheme get text => Theme.of(this).textTheme;

  /// True when the member has asked the OS to reduce motion. Every non-essential
  /// animation checks this before running.
  bool get reduceMotion => MediaQuery.maybeDisableAnimationsOf(this) ?? false;
}
