import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'tokens.dart';
import 'typography.dart';

/// Builds the KOLO [ThemeData] for one appearance.
///
/// Everything visual is declared here or in tokens/typography: there is no
/// styling scattered through screens beyond layout. That is what keeps the
/// product coherent as it grows.
class KoloTheme {
  KoloTheme._();

  static ThemeData light() => _build(KoloColors.light, Brightness.light);


  static ThemeData _build(KoloColors c, Brightness brightness) {
    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      fontFamily: KoloType.family,
    );

    return base.copyWith(
      extensions: <ThemeExtension<dynamic>>[c],
      scaffoldBackgroundColor: c.ground,
      canvasColor: c.ground,
      splashFactory: InkSparkle.splashFactory,

      colorScheme: ColorScheme(
        brightness: brightness,
        primary: c.accent,
        onPrimary: c.accentOn,
        secondary: c.text,
        onSecondary: c.ground,
        error: c.failed,
        onError: Colors.white,
        surface: c.surface,
        onSurface: c.text,
        surfaceContainerHighest: c.surfaceRaised,
        outline: c.hairline,
        outlineVariant: c.hairline,
      ),

      textTheme: KoloType.build(base.textTheme, c),

      // The app draws its own headers: a screen title is a typographic object,
      // not a toolbar. AppBar is kept minimal for the few places that need one.
      appBarTheme: AppBarTheme(
        backgroundColor: c.ground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        foregroundColor: c.text,
        systemOverlayStyle: brightness == Brightness.dark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
        titleTextStyle: KoloType.build(base.textTheme, c).titleLarge,
        iconTheme: IconThemeData(color: c.text, size: 22),
      ),

      dividerTheme: DividerThemeData(
        color: c.hairline,
        thickness: 1,
        space: 1,
      ),

      // --- Buttons -----------------------------------------------------------
      // One primary action style. Citrus fill, ink label, 52 high so it clears
      // the 44pt minimum comfortably and sits right above a thumb.
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: c.accent,
          foregroundColor: c.accentOn,
          disabledBackgroundColor: c.surfaceSunken,
          disabledForegroundColor: c.textFaint,
          minimumSize: const Size.fromHeight(52),
          textStyle: TextStyle(
            fontFamily: KoloType.family,
            fontSize: 15.5,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.1,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(KoloRadius.md),
          ),
          elevation: 0,
        ),
      ),

      // Secondary: outlined, no fill. Used when an action is available but not
      // the thing we want the member to do.
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: c.text,
          minimumSize: const Size.fromHeight(52),
          side: BorderSide(color: c.hairline, width: 1.2),
          textStyle: TextStyle(
            fontFamily: KoloType.family,
            fontSize: 15.5,
            fontWeight: FontWeight.w600,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(KoloRadius.md),
          ),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: c.text,
          textStyle: TextStyle(
            fontFamily: KoloType.family,
            fontSize: 14.5,
            fontWeight: FontWeight.w600,
          ),
          minimumSize: const Size(44, 44),
          padding: const EdgeInsets.symmetric(horizontal: KoloSpace.md),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(KoloRadius.sm),
          ),
        ),
      ),

      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: c.text,
          minimumSize: const Size(44, 44),
          iconSize: 22,
        ),
      ),

      // --- Inputs ------------------------------------------------------------
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        // Raised, not sunken. `surfaceSunken` is darker than the page on a Stone
        // ground, which reads as a disabled control rather than an input.
        fillColor: c.surfaceRaised,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: KoloSpace.lg,
          vertical: KoloSpace.lg,
        ),
        hintStyle: TextStyle(
          fontFamily: KoloType.family,
          color: c.textFaint,
          fontSize: 15,
        ),
        labelStyle: TextStyle(
          fontFamily: KoloType.family,
          color: c.textSoft,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        floatingLabelStyle: TextStyle(
          fontFamily: KoloType.family,
          color: c.text,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
        errorStyle: TextStyle(
          fontFamily: KoloType.family,
          color: c.failed,
          fontSize: 12.5,
          height: 1.35,
        ),
        helperStyle: TextStyle(
          fontFamily: KoloType.family,
          color: c.textFaint,
          fontSize: 12.5,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(KoloRadius.md),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(KoloRadius.md),
          borderSide: BorderSide(color: c.hairline, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(KoloRadius.md),
          borderSide: BorderSide(color: c.text, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(KoloRadius.md),
          borderSide: BorderSide(color: c.failed, width: 1.2),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(KoloRadius.md),
          borderSide: BorderSide(color: c.failed, width: 1.6),
        ),
        prefixIconColor: c.textSoft,
        suffixIconColor: c.textSoft,
      ),

      // --- Surfaces ----------------------------------------------------------
      // Defaults only. KoloCard and KoloSheet apply the design system's own
      // radii and borders; these exist so any stray Material widget is not
      // visually foreign.
      cardTheme: CardThemeData(
        color: c.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KoloRadius.lg),
        ),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KoloRadius.xl),
        ),
        titleTextStyle: KoloType.build(base.textTheme, c).titleLarge,
        contentTextStyle: KoloType.build(base.textTheme, c).bodyMedium,
      ),

      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: c.surface,
        elevation: 0,
        modalElevation: 0,
        showDragHandle: false,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(KoloRadius.xl),
          ),
        ),
      ),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: KoloBrand.ink,
        contentTextStyle: TextStyle(
          fontFamily: KoloType.family,
          color: Colors.white,
          fontSize: 14,
          height: 1.4,
        ),
        actionTextColor: c.accent,
        behavior: SnackBarBehavior.floating,
        insetPadding: const EdgeInsets.all(KoloSpace.lg),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KoloRadius.md),
        ),
        elevation: 0,
      ),

      // Navigation is custom, but the theme is set so any default bar reads
      // correctly rather than falling back to Material purple.
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: c.navBackground,
        surfaceTintColor: Colors.transparent,
        indicatorColor: Colors.transparent,
        elevation: 0,
        height: 64,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: 22,
            color: states.contains(WidgetState.selected) ? c.navActive : c.navInactive,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontFamily: KoloType.family,
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
            color: states.contains(WidgetState.selected) ? c.navActive : c.navInactive,
          ),
        ),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: c.surfaceSunken,
        selectedColor: c.accentWash,
        side: BorderSide(color: c.hairline),
        labelStyle: TextStyle(
          fontFamily: KoloType.family,
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: c.text,
        ),
        secondaryLabelStyle: TextStyle(
          fontFamily: KoloType.family,
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: c.text,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: KoloSpace.md,
          vertical: KoloSpace.sm,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KoloRadius.full),
        ),
        showCheckmark: false,
      ),

      tabBarTheme: TabBarThemeData(
        labelColor: c.text,
        unselectedLabelColor: c.textFaint,
        indicatorColor: c.text,
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: Colors.transparent,
        labelStyle: TextStyle(
          fontFamily: KoloType.family,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: TextStyle(
          fontFamily: KoloType.family,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),

      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: c.text,
        linearTrackColor: c.surfaceSunken,
        circularTrackColor: c.surfaceSunken,
        linearMinHeight: 6,
      ),

      // A visible, on-brand focus ring matters most on the web build and with
      // switch/keyboard access.
      focusColor: c.accentWash,
      hoverColor: c.accentWash,
      highlightColor: c.accentWash,

      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: _KoloPageTransition(),
          TargetPlatform.iOS: _KoloPageTransition(),
          TargetPlatform.linux: _KoloPageTransition(),
          TargetPlatform.macOS: _KoloPageTransition(),
          TargetPlatform.windows: _KoloPageTransition(),
        },
      ),
    );
  }
}

/// A restrained slide-and-fade used for every pushed route.
///
/// Deliberately quieter than Material's default zoom and iOS's full-width
/// slide: it reads as a layer moving in rather than a whole new context
/// arriving, which suits an app where people hop between a group and its
/// programme and back.
class _KoloPageTransition extends PageTransitionsBuilder {
  const _KoloPageTransition();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final disabled = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (disabled) return child;
    final curved = CurvedAnimation(
      parent: animation,
      curve: KoloMotion.enter,
      reverseCurve: KoloMotion.exit,
    );
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0.025, 0),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    );
  }
}
