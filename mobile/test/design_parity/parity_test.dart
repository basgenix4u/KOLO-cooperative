import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kolo/design/navigation.dart';
import 'package:kolo/design/theme.dart';
import 'package:kolo/design/tokens.dart';
import 'package:kolo/features/auth/screens/welcome_screen.dart';
import 'package:kolo/features/auth/screens/login_screen.dart';
import 'package:kolo/features/auth/screens/register_screen.dart';
import 'package:kolo/features/chat/screens/messages_screen.dart';

import 'fixtures.dart';

Future<void> renderScreen(
  WidgetTester tester,
  Widget screen, {
  Map<String, Object> routes = const {},
}) async {
  await loadKoloFonts();
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: fixtureOverrides({...defaultRoutes, ...routes}),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: KoloTheme.light(),
        home: screen,
      ),
    ),
  );
  await tester.pumpAndSettle(const Duration(milliseconds: 60));
}

Future<void> renderWithTabBar(
  WidgetTester tester,
  Widget screen, {
  int index = 0,
  int unread = 0,
  Map<String, Object> routes = const {},
}) async {
  await renderScreen(
    tester,
    Scaffold(
      backgroundColor: const Color(0xFFEFEDE6),
      body: Column(
        children: [
          const KoloStatusBar(),
          Expanded(child: screen),
        ],
      ),
      bottomNavigationBar: KoloBottomNav(
        index: index,
        unread: unread,
        hasAlerts: index == 0,
        onSelect: (_) {},
        onPay: () {},
      ),
    ),
    routes: routes,
  );
}

void main() {
  testWidgets('SCR-002 welcome', (tester) async {
    await renderScreen(tester, const WelcomeScreen());
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/scr-002-welcome.png'),
    );
  });

  testWidgets('SCR-009 sign in', (tester) async {
    await renderScreen(tester, const LoginScreen());
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/scr-009-sign-in.png'),
    );
  });

  testWidgets('SCR-006 create your account', (tester) async {
    await renderScreen(tester, const RegisterScreen());
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/scr-006-register.png'),
    );
  });

  testWidgets('SCR-075 conversations', (tester) async {
    await renderWithTabBar(
      tester,
      const SafeArea(bottom: false, child: MessagesScreen()),
      index: 2,
      unread: 5,
    );
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/scr-075-conversations.png'),
    );
  });

  test('the tab bar geometry is the design geometry', () {
    expect(KoloRadius.sm, 10);
    expect(KoloRadius.md, 14);
    expect(KoloRadius.lg, 18);
    expect(KoloRadius.xl, 24);
    expect(KoloColors.light.ground, const Color(0xFFEFEDE6));
    expect(KoloColors.light.surfaceRaised, const Color(0xFFFFFFFF));
    expect(KoloColors.light.hairline, const Color(0xFFE2E0D8));
  });
}
