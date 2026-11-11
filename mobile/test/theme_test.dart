import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kolo/app.dart';
import 'package:kolo/core/api/providers.dart';
import 'package:kolo/core/api/token_store.dart';
import 'package:kolo/core/theme/kolo_theme.dart';
import 'package:kolo/core/theme/theme_mode.dart';
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
class _ForcedMode extends ThemeModeController {
  _ForcedMode(ThemeMode mode) {
    state = mode;
  }
}

/// WCAG 2.1 relative luminance and contrast ratio.
///
/// Uses the `red`/`green`/`blue` accessors: this SDK predates `Color.r`, which
/// arrived in a later Flutter.
double _relativeLuminance(Color colour) {
  double channel(double c) => c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(colour.red / 255) +
      0.7152 * channel(colour.green / 255) +
      0.0722 * channel(colour.blue / 255);
}

double contrast(Color a, Color b) {
  final la = _relativeLuminance(a);
  final lb = _relativeLuminance(b);
  final lighter = math.max(la, lb);
  final darker = math.min(la, lb);
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  group('theme construction', () {
    test('both themes build and expose a palette', () {
      final light = KoloTheme.light();
      final dark = KoloTheme.dark();

      expect(light.brightness, Brightness.light);
      expect(dark.brightness, Brightness.dark);
      expect(light.extension<KoloPalette>(), isNotNull);
      expect(dark.extension<KoloPalette>(), isNotNull);
      expect(light.scaffoldBackgroundColor, KoloColors.cloud);
      expect(dark.scaffoldBackgroundColor, KoloColors.inkGround);
    });

    test('dark mode is a real palette, not the light one repainted', () {
      const light = KoloPalette.light;
      const dark = KoloPalette.dark;

      // Surfaces relate differently at night: in daylight a card is white on a
      // tinted ground; at night it is lighter than the ground so elevation
      // still reads without shadows.
      expect(_relativeLuminance(dark.surface), greaterThan(_relativeLuminance(dark.ground)));
      expect(_relativeLuminance(light.surface), greaterThan(_relativeLuminance(light.ground)));

      expect(dark.text, isNot(light.text));
      // Accents are lifted, not reused: daylight indigo dies on near-black.
      expect(dark.accent, isNot(light.accent));
      expect(dark.money, isNot(light.money));
      // And the label on the accent flips, because the accent got lighter.
      expect(dark.accentOn, isNot(light.accentOn));
    });
  });

  group('readability', () {
    test('copy is legible on its own background in both themes', () {
      for (final (name, palette) in [('light', KoloPalette.light), ('dark', KoloPalette.dark)]) {
        // WCAG AA for normal text is 4.5:1, for large text 3:1. Body copy is at
        // the smaller end, so hold the stricter line where it applies.
        expect(contrast(palette.text, palette.ground), greaterThan(4.5),
            reason: '$name: primary text on the ground');
        expect(contrast(palette.text, palette.surface), greaterThan(4.5),
            reason: '$name: primary text on a card');
        expect(contrast(palette.textSoft, palette.surface), greaterThan(4.5),
            reason: '$name: secondary text on a card');
        expect(contrast(palette.accentOn, palette.accent), greaterThan(4.5),
            reason: '$name: the label on a primary button');
      }
    });

    test('status colours stay distinguishable from their own tint', () {
      for (final (name, palette) in [('light', KoloPalette.light), ('dark', KoloPalette.dark)]) {
        expect(contrast(palette.success, palette.successSoft), greaterThan(3.0),
            reason: '$name: success pill');
        expect(contrast(palette.danger, palette.dangerSoft), greaterThan(3.0),
            reason: '$name: danger pill');
        expect(contrast(palette.warning, palette.warningSoft), greaterThan(3.0),
            reason: '$name: warning pill');
        expect(contrast(palette.moneyInk, palette.moneySoft), greaterThan(4.5),
            reason: '$name: money pill uses the readable citrus');
      }
    });

    test('money text is legible, since it is the thing being read', () {
      for (final (name, palette) in [('light', KoloPalette.light), ('dark', KoloPalette.dark)]) {
        expect(contrast(palette.text, palette.surface), greaterThan(4.5),
            reason: '$name: an amount on a card must be unambiguous');
        expect(contrast(palette.moneyInk, palette.surface), greaterThan(4.5),
            reason: '$name: an amount highlighted in citrus must be readable');

        // The bright citrus is a fill, so it is judged as a surface with dark
        // text on it rather than as text in its own right.
        expect(contrast(palette.moneyOn, palette.money), greaterThan(4.5),
            reason: '$name: the label on a citrus fill');
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
            themeModeProvider.overrideWith((ref) => _ForcedMode(ThemeMode.dark)),
          ],
          child: const KoloApp(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Money you pool together'), findsOneWidget);

      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(app.themeMode, ThemeMode.dark);
      expect(app.darkTheme, isNotNull);

      // The scaffold actually resolves dark, not just the configuration.
      final context = tester.element(find.byType(Scaffold).first);
      expect(Theme.of(context).brightness, Brightness.dark);
      expect(Theme.of(context).scaffoldBackgroundColor, KoloColors.inkGround);
    });

    testWidgets('an explicit choice overrides the system setting', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            tokenStoreProvider.overrideWithValue(_EmptyTokenStore()),
            sessionProvider.overrideWith((ref) async => null),
            myGroupsProvider.overrideWith((ref) async => const []),
            myObligationsProvider.overrideWith((ref) async => const []),
            themeModeProvider.overrideWith((ref) => _ForcedMode(ThemeMode.light)),
          ],
          child: const KoloApp(),
        ),
      );
      await tester.pumpAndSettle();

      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(app.themeMode, ThemeMode.light);

      final context = tester.element(find.byType(Scaffold).first);
      expect(Theme.of(context).brightness, Brightness.light);
    });

    test('each option is labelled in words a member would use', () {
      expect(themeModeLabel(ThemeMode.system), 'Match my phone');
      expect(themeModeLabel(ThemeMode.light), 'Always light');
      expect(themeModeLabel(ThemeMode.dark), 'Always dark');
    });
  });
}
