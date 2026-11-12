import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/theme/kolo_theme.dart';
import 'core/theme/theme_mode.dart';
import 'features/auth/auth_controller.dart';
import 'features/auth/screens/login_screen.dart';
import 'features/auth/screens/register_screen.dart';
import 'features/auth/screens/verify_screen.dart';
import 'features/chat/screens/conversation_screen.dart';
import 'features/groups/screens/create_group_screen.dart';
import 'features/groups/screens/group_detail_screen.dart';
import 'features/groups/screens/home_screen.dart';
import 'features/groups/screens/join_group_screen.dart';
import 'features/notifications/notifications_screen.dart';
import 'features/profile/profile_screen.dart';
import 'features/savings/screens/contribute_screen.dart';
import 'features/savings/screens/payouts_screen.dart';
import 'features/savings/screens/programme_detail_screen.dart';
import 'features/savings/screens/vote_screen.dart';

class KoloApp extends ConsumerStatefulWidget {
  const KoloApp({super.key});

  @override
  ConsumerState<KoloApp> createState() => _KoloAppState();
}

class _KoloAppState extends ConsumerState<KoloApp> {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _router = _buildRouter();
  }

  GoRouter _buildRouter() {
    return GoRouter(
      initialLocation: '/',
      // A single redirect decides signed-in vs signed-out. Screens never each
      // re-check auth, which is how guard logic drifts out of sync.
      redirect: (context, state) {
        final session = ref.read(sessionProvider);
        final path = state.uri.path;
        final onAuthPath = path.startsWith('/welcome') ||
            path.startsWith('/login') ||
            path.startsWith('/register') ||
            path.startsWith('/verify');

        final user = session.valueOrNull;
        final signedIn = user != null;

        if (session.isLoading && !session.hasValue) return null;
        if (!signedIn && !onAuthPath) return '/welcome';
        if (signedIn && onAuthPath && !path.startsWith('/verify')) return '/';
        return null;
      },
      refreshListenable: _ProviderNotifier(ref, sessionProvider),
      routes: [
        GoRoute(path: '/welcome', builder: (_, __) => const WelcomeScreen()),
        GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
        GoRoute(path: '/register', builder: (_, __) => const RegisterScreen()),
        GoRoute(
          path: '/verify',
          builder: (_, state) => VerifyScreen(email: state.uri.queryParameters['email'] ?? ''),
        ),
        GoRoute(path: '/', builder: (_, __) => const HomeScreen()),
        GoRoute(
          path: '/groups/new',
          builder: (_, __) => const CreateGroupScreen(),
        ),
        GoRoute(
          path: '/groups/join',
          builder: (_, __) => const JoinGroupScreen(),
        ),
        GoRoute(
          path: '/groups/:slug',
          builder: (_, state) => GroupDetailScreen(slug: state.pathParameters['slug']!),
          routes: [
            GoRoute(
              path: 'chat',
              builder: (_, state) => ConversationScreen(slug: state.pathParameters['slug']!),
            ),
            GoRoute(
              path: 'vote',
              builder: (_, state) => VoteScreen(slug: state.pathParameters['slug']!),
            ),
          ],
        ),
        GoRoute(
          path: '/programmes/:id',
          builder: (_, state) => ProgrammeDetailScreen(programmeId: state.pathParameters['id']!),
          routes: [
            GoRoute(
              path: 'payouts',
              builder: (_, state) {
                // Passed through `extra` because the screen needs the group's
                // pool figure. A cold deep link still works: it falls back to
                // the programme id and asks the server for the rest.
                final extra = (state.extra as Map?) ?? const {};
                return PayoutsScreen(
                  programmeId: state.pathParameters['id']!,
                  programmeName: '${extra['name'] ?? 'Programme'}',
                  currency: '${extra['currency'] ?? 'NGN'}',
                  slug: '${extra['slug'] ?? ''}',
                );
              },
            ),
            GoRoute(
              path: 'contribute',
              builder: (_, state) => ContributeScreen(
                programmeId: state.pathParameters['id']!,
                obligationId: state.uri.queryParameters['obligation'],
                suggestedMinor: int.tryParse(state.uri.queryParameters['amount'] ?? ''),
              ),
            ),
          ],
        ),
        GoRoute(path: '/notifications', builder: (_, __) => const NotificationsScreen()),
        GoRoute(path: '/profile', builder: (_, __) => const ProfileScreen()),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // When the API client gives up on a session, send the member to sign-in
    // rather than leaving them on a screen that cannot load.
    ref.listen(sessionProvider, (previous, next) {
      if (next.hasValue && next.valueOrNull == null) {
        final location = _router.routerDelegate.currentConfiguration.uri.path;
        if (!location.startsWith('/welcome') && !location.startsWith('/login')) {
          _router.go('/welcome');
        }
      }
    });

    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp.router(
      title: 'KOLO',
      debugShowCheckedModeBanner: false,
      theme: KoloTheme.light(),
      darkTheme: KoloTheme.dark(),
      themeMode: themeMode,
      routerConfig: _router,
    );
  }
}

/// Bridges a Riverpod provider to GoRouter's refresh mechanism.
///
/// A StatefulWidget's `ref` is a `WidgetRef`, which cannot outlive the widget, so
/// the notifier keeps the subscription and disposes it with itself.
class _ProviderNotifier extends ChangeNotifier {
  _ProviderNotifier(WidgetRef ref, ProviderListenable<AsyncValue<dynamic>> provider) {
    // `listen` on a WidgetRef returns void; `listenManual` gives us a
    // subscription we own and can cancel when the router is rebuilt.
    _subscription = ref.listenManual<AsyncValue<dynamic>>(provider, (_, __) => notifyListeners());
  }

  ProviderSubscription<AsyncValue<dynamic>>? _subscription;

  @override
  void dispose() {
    _subscription?.close();
    super.dispose();
  }
}

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = context.kolo;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Spacer(),
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: palette.accent,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Center(
                  child: Text(
                    'K',
                    style: TextStyle(
                      color: palette.surface,
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 28),
              Text(
                'Money you pool together,\naccounted for properly.',
                style: Theme.of(context).textTheme.displaySmall?.copyWith(height: 1.2),
              ),
              const SizedBox(height: 16),
              Text(
                'Ajo, esusu, adashe — the groups you already trust, with every contribution '
                'recorded and every payout backed by money that has actually been collected.',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: palette.textSoft),
              ),
              const Spacer(),
              FilledButton(
                onPressed: () => context.push('/register'),
                child: const Text('Create an account'),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => context.push('/login'),
                child: const Text('I already have an account'),
              ),
              const SizedBox(height: 16),
              Center(
                child: Text(
                  'Sandbox build — no real money moves',
                  style: TextStyle(fontSize: 12, color: palette.textFaint),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
