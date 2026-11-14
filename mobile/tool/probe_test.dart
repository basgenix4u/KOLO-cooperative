import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kolo/app.dart';
import 'package:go_router/go_router.dart';
import 'package:kolo/core/api/providers.dart';
import 'package:kolo/core/api/token_store.dart';
import 'package:kolo/features/auth/auth_controller.dart';
import 'package:kolo/core/theme/theme_mode.dart';
import 'package:kolo/features/auth/screens/register_screen.dart';
import 'package:kolo/features/auth/screens/welcome_screen.dart';

class _Empty extends TokenStore {
  @override Future<String?> accessToken() async => null;
  @override Future<String?> refreshToken() async => null;
  @override Future<bool> get hasSession async => false;
}
class _Mode extends ThemeModeController {
  @override ThemeMode build() => ThemeMode.light;
  @override Future<void> set(ThemeMode m) async => state = m;
}
void main() {
  testWidgets('probe register route', (t) async {
    await t.pumpWidget(ProviderScope(overrides: [
      tokenStoreProvider.overrideWithValue(_Empty()),
      sessionProvider.overrideWith((ref) async => null),
      themeModeProvider.overrideWith(_Mode.new),
    ], child: const KoloApp(initialLocation: '/register')));
    await t.pumpAndSettle(const Duration(seconds: 2));
    final ctx = t.element(find.byType(WelcomeScreen));
    final router = GoRouter.of(ctx);
    debugPrint('router location: ${router.routerDelegate.currentConfiguration.uri}');
    debugPrint('RegisterScreen widget: ${find.byType(RegisterScreen).evaluate().length}');
    debugPrint('WelcomeScreen widget: ${find.byType(WelcomeScreen).evaluate().length}');
    debugPrint('FULL NAME label: ${find.text('FULL NAME').evaluate().length}');
    for (final e in find.byType(Text).evaluate().take(12)) {
      debugPrint('  text: ${(e.widget as Text).data}');
    }
  });
}
