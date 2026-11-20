import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kolo/app.dart';
import 'package:kolo/core/api/providers.dart';
import 'package:kolo/core/api/token_store.dart';
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
    test('the theme builds with the KOLO palette attached', () {
      final light = KoloTheme.light();

      expect(light.brightness, Brightness.light);
      expect(light.extension<KoloColors>(), isNotNull);
      expect(light.scaffoldBackgroundColor, KoloColors.light.ground);
    });

    test('the four brand colours are the authoritative values', () {
      expect(KoloBrand.ink, const Color(0xFF101820));
      expect(KoloBrand.citrus, const Color(0xFFD5F45A));
      expect(KoloBrand.stone, const Color(0xFFE9E7DF));
      expect(KoloBrand.slate, const Color(0xFF64717C));
    });

    test('a card sits above the page ground', () {
      const c = KoloColors.light;
      expect(_relativeLuminance(c.surface),
          greaterThan(_relativeLuminance(c.ground)));
    });

    test('citrus label contrast forces ink', () {
      expect(KoloColors.light.accentOn, KoloBrand.ink);
    });
  });

  group('readability', () {
    test('every text tone is legible on every light surface', () {
      const c = KoloColors.light;
      for (final (label, tone) in [
        ('primary text', c.text),
        ('secondary text', c.textSoft),
      ]) {
        for (final (surfaceName, surface) in [
          ('ground', c.ground),
          ('card', c.surface),
          ('raised', c.surfaceRaised),
        ]) {
          expect(contrast(tone, surface), greaterThan(4.5),
              reason: '$label on $surfaceName must clear WCAG AA');
        }
      }
    });

    test('the tertiary tone is the design value, and the design value is weak', () {
      // --text-faint #6E7883 is 3.83:1 on the page ground, which is below AA for
      // body copy. The value is kept because it is what the design specifies and
      // the token is only ever used for uppercase eyebrows, timestamps and other
      // metadata that is duplicated by an icon or a label beside it. Any string a
      // member must read to act is set in text or textSoft, never here.
      const c = KoloColors.light;
      expect(c.textFaint, const Color(0xFF6E7883));
      expect(contrast(c.textFaint, c.ground), greaterThan(3.0));
      expect(contrast(c.textFaint, c.ground), lessThan(4.5));
      expect(contrast(c.textSoft, c.ground), greaterThan(4.5));
    });

    test('a label on a primary button is readable', () {
      const c = KoloColors.light;
      expect(contrast(c.accentOn, c.accent), greaterThan(4.5));
    });

    test('citrus used as text is a deepened tone, not the brand fill', () {
      const c = KoloColors.light;
      expect(contrast(c.accentText, c.ground), greaterThan(4.5));
      expect(contrast(KoloBrand.citrus, c.ground), lessThan(2.0));
    });

    test('status colours are distinguishable from their own tint', () {
      const c = KoloColors.light;
      expect(contrast(c.settled, c.settledWash), greaterThan(3.0));
      expect(contrast(c.pending, c.pendingWash), greaterThan(3.0));
      expect(contrast(c.failed, c.failedWash), greaterThan(3.0));
    });
  });

  group('theme preference', () {
    testWidgets('the app renders in the light theme only', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            tokenStoreProvider.overrideWithValue(_EmptyTokenStore()),
            sessionProvider.overrideWith((ref) async => null),
            myGroupsProvider.overrideWith((ref) async => const []),
            myObligationsProvider.overrideWith((ref) async => const []),
          ],
          child: const KoloApp(),
        ),
      );
      await tester.pumpAndSettle();

      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(app.darkTheme, isNull);
      expect(app.theme!.scaffoldBackgroundColor, KoloColors.light.ground);
    });
  });
}
