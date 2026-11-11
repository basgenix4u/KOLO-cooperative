import 'package:flutter/material.dart';

/// KOLO's visual language — "Ink & Citrus".
///
/// Warm rather than corporate: these are savings groups of friends and family,
/// not a bank. Ink is the deep indigo that carries trust and structure; citrus
/// is the warm amber reserved for money and for the one action that matters on
/// any given screen. Green is kept for confirmation only — green-for-money reads
/// as "profit", and this app is about pooling, not gain.
class KoloColors {
  KoloColors._();

  // --- Ink (light) --------------------------------------------------------
  static const Color ink = Color(0xFF14142B);
  static const Color inkSoft = Color(0xFF4E4B66);
  static const Color inkFaint = Color(0xFF8A87A0);
  static const Color cloud = Color(0xFFF7F6FB);
  static const Color white = Color(0xFFFFFFFF);

  // --- Citrus -------------------------------------------------------------
  static const Color indigo = Color(0xFF2D2A8C);
  static const Color indigoLight = Color(0xFF5B57D1);
  static const Color amber = Color(0xFFE8A33D);
  static const Color amberSoft = Color(0xFFFDF3E2);

  /// Citrus as *text*. The bright amber above is 2.2:1 on white — unreadable as
  /// copy, fine as a fill behind dark text. Amounts and money labels use this
  /// deeper tone instead, which holds 5.9:1 on white and 5.4:1 on the cream tint.
  static const Color amberInk = Color(0xFF8A5A12);

  // --- Meaning ------------------------------------------------------------
  static const Color success = Color(0xFF1E8A5F);
  static const Color successSoft = Color(0xFFE6F4EE);
  static const Color danger = Color(0xFFC0392B);
  static const Color dangerSoft = Color(0xFFFBEAE8);
  static const Color warning = Color(0xFFB7791F);
  static const Color warningSoft = Color(0xFFFDF6E3);

  static const Color divider = Color(0xFFE8E6F0);

  // --- Night -------------------------------------------------------------
  //
  // Not the light palette inverted. The ground drops to near-black with a blue
  // bias rather than neutral grey, surfaces sit *above* it in lightness so
  // elevation still reads without shadows, and the accents are lifted: the
  // daylight indigo has far too little contrast on a dark ground, and the
  // daylight amber goes muddy. The soft tints become deep, desaturated washes
  // rather than the pale creams used in daylight.
  static const Color inkGround = Color(0xFF0E0E18);
  static const Color inkSurface = Color(0xFF1A1A28);
  static const Color inkSurfaceHigh = Color(0xFF242436);
  static const Color inkText = Color(0xFFF3F2F9);
  static const Color inkTextSoft = Color(0xFFB4B1C6);
  static const Color inkTextFaint = Color(0xFF8B87A0);
  static const Color inkDivider = Color(0xFF2E2E42);

  static const Color indigoNight = Color(0xFF9C98FF);
  static const Color amberNight = Color(0xFFF5BE63);
  static const Color successNight = Color(0xFF59D3A0);
  static const Color dangerNight = Color(0xFFFF8A7A);
  static const Color warningNight = Color(0xFFE8B851);

  static const Color successSoftNight = Color(0xFF14311F);
  static const Color dangerSoftNight = Color(0xFF3A171B);
  static const Color warningSoftNight = Color(0xFF352810);
  static const Color amberSoftNight = Color(0xFF352810);
}

/// Semantic colours resolved for the active brightness.
///
/// Screens read colours from here (via `context.kolo`) rather than from
/// [KoloColors] directly. Referencing a light-mode constant in a widget is how
/// dark mode ends up half-applied: the widget compiles, and then renders
/// mid-grey text on a black card.
@immutable
class KoloPalette extends ThemeExtension<KoloPalette> {
  const KoloPalette({
    required this.ground,
    required this.surface,
    required this.surfaceHigh,
    required this.text,
    required this.textSoft,
    required this.textFaint,
    required this.divider,
    required this.accent,
    required this.accentOn,
    required this.money,
    required this.moneyInk,
    required this.moneyOn,
    required this.moneySoft,
    required this.success,
    required this.successSoft,
    required this.danger,
    required this.dangerSoft,
    required this.warning,
    required this.warningSoft,
  });

  final Color ground;
  final Color surface;
  final Color surfaceHigh;
  final Color text;
  final Color textSoft;
  final Color textFaint;
  final Color divider;
  final Color accent;

  /// The label colour to use *on top of* [accent].
  final Color accentOn;
  /// Citrus for fills, bars and highlights.
  final Color money;

  /// Citrus for text and glyphs: the same hue, deepened enough to read.
  final Color moneyInk;

  /// The label colour to use on top of a citrus fill.
  ///
  /// Ink in both themes. Citrus is a light colour, so a white label on it is
  /// barely visible — and in dark mode the near-white body colour is worse
  /// still, at 1.5:1.
  final Color moneyOn;
  final Color moneySoft;
  final Color success;
  final Color successSoft;
  final Color danger;
  final Color dangerSoft;
  final Color warning;
  final Color warningSoft;

  static const KoloPalette light = KoloPalette(
    ground: KoloColors.cloud,
    surface: KoloColors.white,
    surfaceHigh: KoloColors.cloud,
    text: KoloColors.ink,
    textSoft: KoloColors.inkSoft,
    textFaint: KoloColors.inkFaint,
    divider: KoloColors.divider,
    accent: KoloColors.indigo,
    accentOn: KoloColors.white,
    money: KoloColors.amber,
    moneyInk: KoloColors.amberInk,
    moneyOn: KoloColors.ink,
    moneySoft: KoloColors.amberSoft,
    success: KoloColors.success,
    successSoft: KoloColors.successSoft,
    danger: KoloColors.danger,
    dangerSoft: KoloColors.dangerSoft,
    warning: KoloColors.warning,
    warningSoft: KoloColors.warningSoft,
  );

  static const KoloPalette dark = KoloPalette(
    ground: KoloColors.inkGround,
    surface: KoloColors.inkSurface,
    surfaceHigh: KoloColors.inkSurfaceHigh,
    text: KoloColors.inkText,
    textSoft: KoloColors.inkTextSoft,
    textFaint: KoloColors.inkTextFaint,
    divider: KoloColors.inkDivider,
    accent: KoloColors.indigoNight,
    // A lifted indigo needs a dark label, not white.
    accentOn: KoloColors.inkGround,
    money: KoloColors.amberNight,
    // Already light enough to serve as text on a dark ground.
    moneyInk: KoloColors.amberNight,
    // A dark label on a bright fill, in both themes.
    moneyOn: KoloColors.inkGround,
    moneySoft: KoloColors.amberSoftNight,
    success: KoloColors.successNight,
    successSoft: KoloColors.successSoftNight,
    danger: KoloColors.dangerNight,
    dangerSoft: KoloColors.dangerSoftNight,
    warning: KoloColors.warningNight,
    warningSoft: KoloColors.warningSoftNight,
  );

  @override
  KoloPalette copyWith({
    Color? ground,
    Color? surface,
    Color? surfaceHigh,
    Color? text,
    Color? textSoft,
    Color? textFaint,
    Color? divider,
    Color? accent,
    Color? accentOn,
    Color? money,
    Color? moneyInk,
    Color? moneyOn,
    Color? moneySoft,
    Color? success,
    Color? successSoft,
    Color? danger,
    Color? dangerSoft,
    Color? warning,
    Color? warningSoft,
  }) {
    return KoloPalette(
      ground: ground ?? this.ground,
      surface: surface ?? this.surface,
      surfaceHigh: surfaceHigh ?? this.surfaceHigh,
      text: text ?? this.text,
      textSoft: textSoft ?? this.textSoft,
      textFaint: textFaint ?? this.textFaint,
      divider: divider ?? this.divider,
      accent: accent ?? this.accent,
      accentOn: accentOn ?? this.accentOn,
      money: money ?? this.money,
      moneyInk: moneyInk ?? this.moneyInk,
      moneyOn: moneyOn ?? this.moneyOn,
      moneySoft: moneySoft ?? this.moneySoft,
      success: success ?? this.success,
      successSoft: successSoft ?? this.successSoft,
      danger: danger ?? this.danger,
      dangerSoft: dangerSoft ?? this.dangerSoft,
      warning: warning ?? this.warning,
      warningSoft: warningSoft ?? this.warningSoft,
    );
  }

  @override
  KoloPalette lerp(ThemeExtension<KoloPalette>? other, double t) {
    if (other is! KoloPalette) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return KoloPalette(
      ground: mix(ground, other.ground),
      surface: mix(surface, other.surface),
      surfaceHigh: mix(surfaceHigh, other.surfaceHigh),
      text: mix(text, other.text),
      textSoft: mix(textSoft, other.textSoft),
      textFaint: mix(textFaint, other.textFaint),
      divider: mix(divider, other.divider),
      accent: mix(accent, other.accent),
      accentOn: mix(accentOn, other.accentOn),
      money: mix(money, other.money),
      moneyInk: mix(moneyInk, other.moneyInk),
      moneyOn: mix(moneyOn, other.moneyOn),
      moneySoft: mix(moneySoft, other.moneySoft),
      success: mix(success, other.success),
      successSoft: mix(successSoft, other.successSoft),
      danger: mix(danger, other.danger),
      dangerSoft: mix(dangerSoft, other.dangerSoft),
      warning: mix(warning, other.warning),
      warningSoft: mix(warningSoft, other.warningSoft),
    );
  }
}

extension KoloPaletteContext on BuildContext {
  /// The active palette. Falls back to light so a widget rendered outside the
  /// app (in a test, say) still draws something sensible.
  KoloPalette get kolo => Theme.of(this).extension<KoloPalette>() ?? KoloPalette.light;
}

class KoloTheme {
  KoloTheme._();

  static ThemeData light() => _build(Brightness.light, KoloPalette.light);

  static ThemeData dark() => _build(Brightness.dark, KoloPalette.dark);

  static ThemeData _build(Brightness brightness, KoloPalette palette) {
    final isDark = brightness == Brightness.dark;
    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: palette.ground,
      colorScheme: ColorScheme.fromSeed(
        seedColor: isDark ? KoloColors.indigoNight : KoloColors.indigo,
        primary: palette.accent,
        secondary: palette.money,
        surface: palette.surface,
        onSurface: palette.text,
        error: palette.danger,
        brightness: brightness,
      ),
    );

    return base.copyWith(
      extensions: [palette],
      textTheme: _textTheme(base.textTheme, palette),
      appBarTheme: AppBarTheme(
        backgroundColor: palette.ground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        foregroundColor: palette.text,
        titleTextStyle: TextStyle(
          color: palette.text,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
        ),
      ),
      cardTheme: CardTheme(
        color: palette.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: palette.divider),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: palette.accent,
          foregroundColor: palette.accentOn,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: palette.accent,
          minimumSize: const Size.fromHeight(52),
          side: BorderSide(color: palette.divider),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: palette.accent),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: palette.surfaceHigh,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: palette.divider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: palette.divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: palette.accent, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: palette.danger),
        ),
        hintStyle: TextStyle(color: palette.textFaint),
        labelStyle: TextStyle(color: palette.textSoft),
      ),
      dividerTheme: DividerThemeData(color: palette.divider, thickness: 1, space: 1),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark ? palette.surfaceHigh : KoloColors.ink,
        contentTextStyle: TextStyle(color: isDark ? palette.text : KoloColors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: palette.surfaceHigh,
        side: BorderSide(color: palette.divider),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        labelStyle: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: palette.textSoft),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: palette.accent),
      iconTheme: IconThemeData(color: palette.textSoft),
      listTileTheme: ListTileThemeData(iconColor: palette.textSoft, textColor: palette.text),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: palette.surface,
        surfaceTintColor: Colors.transparent,
        dragHandleColor: palette.divider,
      ),
      dialogTheme: DialogTheme(
        backgroundColor: palette.surface,
        surfaceTintColor: Colors.transparent,
      ),
    );
  }

  static TextTheme _textTheme(TextTheme base, KoloPalette palette) {
    return base.copyWith(
      displaySmall: TextStyle(
        fontSize: 32, fontWeight: FontWeight.w700, color: palette.text, letterSpacing: -0.6,
      ),
      headlineMedium: TextStyle(
        fontSize: 24, fontWeight: FontWeight.w700, color: palette.text, letterSpacing: -0.4,
      ),
      titleLarge: TextStyle(
        fontSize: 18, fontWeight: FontWeight.w700, color: palette.text, letterSpacing: -0.2,
      ),
      titleMedium: TextStyle(
        fontSize: 16, fontWeight: FontWeight.w600, color: palette.text,
      ),
      bodyLarge: TextStyle(fontSize: 16, color: palette.text, height: 1.45),
      bodyMedium: TextStyle(fontSize: 14, color: palette.textSoft, height: 1.45),
      bodySmall: TextStyle(fontSize: 12.5, color: palette.textFaint, height: 1.4),
      labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: palette.text),
    );
  }

  /// Tabular figures for money: columns of amounts must line up, and a digit
  /// that changes width while a value animates looks like a glitch.
  static TextStyle moneyLarge(Color color) => TextStyle(
        fontSize: 30,
        fontWeight: FontWeight.w700,
        color: color,
        letterSpacing: -0.8,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  static TextStyle moneyMedium(Color color) => TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: color,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  static TextStyle moneySmall(Color color) => TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: color,
        fontFeatures: const [FontFeature.tabularFigures()],
      );
}
