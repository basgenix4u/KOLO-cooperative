import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kolo/app.dart';
import 'package:kolo/core/api/providers.dart';
import 'package:kolo/core/api/token_store.dart';
import 'package:kolo/core/theme/theme_mode.dart';
import 'package:kolo/design/theme.dart';
import 'package:kolo/design/tokens.dart';
import 'package:kolo/features/auth/auth_controller.dart';
import 'package:kolo/features/savings/savings_providers.dart';

class _EmptyTokenStore extends TokenStore {
  @override
  Future<String?> accessToken() async => null;

  @override
  Future<String?> refreshToken() async => null;

  @override
  Future<bool> get hasSession async => false;
}

/// A controller pinned to one mode, so a test never depends on what is stored on
/// the device or on the host platform's brightness.
///
/// Overrides the provider with `overrideWith` rather than replacing a state
/// value, because a Riverpod 3 `Notifier` is built through its factory and only
/// then has its state set. Doing it in `build()` keeps this valid on both
/// Riverpod 2 and 3.
class _ForcedMode extends ThemeModeController {
  _ForcedMode(this._mode);

  final ThemeMode _mode;

  @override
  ThemeMode build() => _mode;

  // Never touch shared preferences from a test: the stored value would leak
  // between tests and, on a real device, pin the theme for the next launch.
  @override
  Future<void> set(ThemeMode mode) async {
    state = mode;
  }
}

/// WCAG 2.1 relative luminance and contrast ratio.
///
/// Uses channel accessors that exist on every Flutter this app supports, so the
/// maths does not depend on the newer `Color.r/.g/.b` API.
double _relativeLuminance(Color colour) {
  double channel(double c) =>
      c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(colour.red / 255) +
      0.7152 * channel(colour.green / 255) +
      0.0722 * channel(colour.blue / 255);
}

double contrast(Color a, Color b) {
  final la = _relativeLuminance(a);
  final lb = _relativeLuminance(b);
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  group('theme construction', () {
    test('both appearances build with the KOLO palette attached', () {
      final light = KoloTheme.light();
      final dark = KoloTheme.dark();

      expect(light.brightness, Brightness.light);
      expect(dark.brightness, Brightness.dark);
      expect(light.extension<KoloColors>(), isNotNull);
      expect(dark.extension<KoloColors>(), isNotNull);

      expect(light.scaffoldBackgroundColor, KoloColors.light.ground);
      expect(dark.scaffoldBackgroundColor, KoloColors.dark.ground);
    });

    test('the four brand colours are the authoritative values', () {
      // If any of these drift, the product stops being Ink & Citrus.
      expect(KoloBrand.ink, const Color(0xFF101820));
      expect(KoloBrand.citrus, const Color(0xFFD5F45A));
      expect(KoloBrand.stone, const Color(0xFFE9E7DF));
      expect(KoloBrand.slate, const Color(0xFF64717C));
    });

    test('dark mode is a real palette, not the light one repainted', () {
      const light = KoloColors.light;
      const dark = KoloColors.dark;

      // Surfaces relate differently at night: in daylight a card is lighter than
      // the Stone ground; at night it is lighter than the ink ground so
      // elevation still reads without shadows.
      expect(_relativeLuminance(dark.surface),
          greaterThan(_relativeLuminance(dark.ground)));
      expect(_relativeLuminance(light.surface),
          greaterThan(_relativeLuminance(light.ground)));

      expect(dark.text, isNot(light.text));
      expect(dark.ground, isNot(light.ground));
      expect(dark.textSoft, isNot(light.textSoft));
      expect(dark.settled, isNot(light.settled));
    });

    test('citrus label contrast forces ink in both appearances', () {
      // Citrus is a light colour. A white label on it is ~1.4:1; ink on it is
      // 14.4:1. The foreground must therefore be ink in either appearance.
      expect(KoloColors.light.accentOn, KoloBrand.ink);
      expect(KoloColors.dark.accentOn, KoloBrand.ink);
    });
  });

  group('readability', () {
    test('every text tone is legible on both light surfaces', () {
      // Light mode is where this is hardest: Stone and Stone-light are both
      // bright, so every tone is checked against the darker of the two.
      const c = KoloColors.light;
      for (final (label, tone) in [
        ('primary text', c.text),
        ('secondary text', c.textSoft),
        ('tertiary text', c.textFaint),
      ]) {
        for (final (surfaceName, surface) in [
          ('ground', c.ground),
          ('card', c.surface),
          ('raised', c.surfaceRaised),
        ]) {
          expect(contrast(tone, surface), greaterThan(4.5),
              reason: 'light: $label on $surfaceName must clear WCAG AA');
        }
      }
    });

    test('every text tone is legible on dark surfaces', () {
      const c = KoloColors.dark;
      for (final (label, tone) in [
        ('primary text', c.text),
        ('secondary text', c.textSoft),
        ('tertiary text', c.textFaint),
      ]) {
        for (final (surfaceName, surface) in [
          ('ground', c.ground),
          ('card', c.surface),
          ('raised', c.surfaceRaised),
        ]) {
          expect(contrast(tone, surface), greaterThan(4.5),
              reason: 'dark: $label on $surfaceName must clear WCAG AA');
        }
      }
    });

    test('a label on a primary button is readable', () {
      for (final (name, c) in [('light', KoloColors.light), ('dark', KoloColors.dark)]) {
        expect(contrast(c.accentOn, c.accent), greaterThan(4.5),
            reason: '$name: the label on a citrus button');
      }
    });

    test('citrus used as text is a deepened tone, not the brand fill', () {
      // The bright citrus is 1.4:1 on Stone, so it may only be used as a fill.
      // Any citrus *copy* goes through accentText.
      const c = KoloColors.light;
      expect(contrast(c.accentText, c.ground), greaterThan(4.5),
          reason: 'light: citrus text on the page ground');
      expect(contrast(KoloBrand.citrus, c.ground), lessThan(2.0),
          reason: 'the raw brand citrus is confirmed unusable as text on Stone');
    });

    test('status colours are distinguishable from their own tint', () {
      // 3:1 is the floor for a non-text UI element. Every pill also carries an
      // icon and a word, so colour is never the only signal.
      for (final (name, c) in [('light', KoloColors.light), ('dark', KoloColors.dark)]) {
        expect(contrast(c.settled, c.settledWash), greaterThan(3.0),
            reason: '$name: settled pill');
        expect(contrast(c.pending, c.pendingWash), greaterThan(3.0),
            reason: '$name: pending pill');
        expect(contrast(c.failed, c.failedWash), greaterThan(3.0),
            reason: '$name: failed pill');
      }
    });
  });

  group('theme preference', () {
    testWidgets('the app can render in dark mode', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            tokenStoreProvider.overrideWithValue(_EmptyTokenStore()),
            sessionProvider.overrideWith((ref) async => null),
            myGroupsProvider.overrideWith((ref) async => const []),
            myObligationsProvider.overrideWith((ref) async => const []),
            themeModeProvider.overrideWith(() => _ForcedMode(ThemeMode.dark)),
          ],
          child: const KoloApp(),
        ),
      );
      await tester.pumpAndSettle();

      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(app.themeMode, ThemeMode.dark);
      expect(app.darkTheme, isNotNull);
      // The dark theme is a real palette, so its ground is the ink colour.
      expect(app.darkTheme!.scaffoldBackgroundColor, KoloColors.dark.ground);
    });

    testWidgets('an explicit choice overrides the system setting', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            tokenStoreProvider.overrideWithValue(_EmptyTokenStore()),
            sessionProvider.overrideWith((ref) async => null),
            myGroupsProvider.overrideWith((ref) async => const []),
            myObligationsProvider.overrideWith((ref) async => const []),
            themeModeProvider.overrideWith(() => _ForcedMode(ThemeMode.light)),
          ],
          child: const KoloApp(),
        ),
      );
      await tester.pumpAndSettle();

      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(app.themeMode, ThemeMode.light);
      expect(app.theme!.scaffoldBackgroundColor, KoloColors.light.ground);
    });

    test('each option is labelled in words a member would use', () {
      expect(themeModeLabel(ThemeMode.system), 'Match my phone');
      expect(themeModeLabel(ThemeMode.light), 'Always light');
      expect(themeModeLabel(ThemeMode.dark), 'Always dark');
    });
  });
}
