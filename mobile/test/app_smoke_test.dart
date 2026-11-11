import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kolo/core/api/providers.dart';
import 'package:kolo/features/savings/savings_providers.dart';
import 'package:kolo/app.dart';
import 'package:kolo/core/api/token_store.dart';
import 'package:kolo/features/auth/auth_controller.dart';

/// A token store with no session, so the app's own redirect logic runs for real
/// instead of being short-circuited by a stub.
class _EmptyTokenStore extends TokenStore {
  @override
  Future<String?> accessToken() async => null;

  @override
  Future<String?> refreshToken() async => null;

  @override
  Future<bool> get hasSession async => false;
}

/// A smoke test of the real app shell.
///
/// Providers that would hit the network are overridden, so this proves the
/// widget tree builds and routes — not that the backend is reachable, which no
/// widget test could show.
void main() {
  testWidgets('the app builds and lands on the welcome screen when signed out',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // No session: the router's redirect must send us to /welcome.
          tokenStoreProvider.overrideWithValue(_EmptyTokenStore()),
          sessionProvider.overrideWith((ref) async => null),
          myGroupsProvider.overrideWith((ref) async => const []),
          myObligationsProvider.overrideWith((ref) async => const []),
        ],
        child: const KoloApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Money you pool together'), findsOneWidget);
    expect(find.text('Create an account'), findsOneWidget);
    expect(find.text('I already have an account'), findsOneWidget);
  });

  testWidgets('the welcome screen is honest about being a sandbox', (tester) async {
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

    // A member must never be left guessing whether money is real.
    expect(find.textContaining('no real money moves'), findsOneWidget);
  });

  testWidgets('sign-in is reachable from the welcome screen', (tester) async {
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

    await tester.tap(find.text('I already have an account'));
    await tester.pumpAndSettle();

    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Sign in'), findsWidgets);
  });
}
