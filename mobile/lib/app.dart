import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/deeplink/deep_links.dart';
import 'core/models/models.dart';
import 'design/shell.dart';
import 'design/theme.dart';
import 'features/auth/auth_controller.dart';
import 'features/auth/screens/login_screen.dart';
import 'features/auth/screens/register_screen.dart';
import 'features/auth/screens/verify_screen.dart';
import 'features/auth/screens/welcome_screen.dart';
import 'features/chat/screens/conversation_screen.dart';
import 'features/chat/screens/messages_screen.dart';
import 'features/groups/screens/create_group_screen.dart';
import 'features/groups/screens/group_detail_screen.dart';
import 'features/groups/screens/groups_tab.dart';
import 'features/groups/screens/home_screen.dart';
import 'features/groups/screens/join_group_screen.dart';
import 'features/notifications/notifications_screen.dart';
import 'features/profile/profile_screen.dart';
import 'features/savings/screens/contribute_screen.dart';
import 'features/savings/screens/contributions_screen.dart';
import 'features/savings/screens/payouts_screen.dart';
import 'features/savings/screens/programme_detail_screen.dart';
import 'features/savings/screens/vote_screen.dart';

class KoloApp extends ConsumerStatefulWidget {
  const KoloApp({super.key, this.initialLocation});

  /// Where the router starts. Null in production, where the redirect decides
  /// based on the session; set by the screenshot harness to render one screen.
  final String? initialLocation;

  @override
  ConsumerState<KoloApp> createState() => _KoloAppState();
}

class _KoloAppState extends ConsumerState<KoloApp> {
  late final GoRouter _router;

  final _links = DeepLinkListener();
  StreamSubscription<DeepLink>? _linkSubscription;

  /// A link that arrived while the member was signed out. The router sends them
  /// to sign-in, and the destination would otherwise be forgotten — so it is
  /// held here and opened once a session exists. An invitation is useless if
  /// creating an account loses it.
  DeepLink? _pending;

  @override
  void initState() {
    super.initState();
    _router = _buildRouter();
    _listenForLinks();
  }

  Future<void> _listenForLinks() async {
    try {
      // The link that launched a cold start is delivered once, here.
      final initial = await _links.initial();
      if (initial != null) {
        _open(initial);
      }
      _linkSubscription = _links.stream().listen(_open);
    } catch (error) {
      // Deep linking is a convenience. A platform that cannot deliver links
      // must not stop the app from opening.
      debugPrint('KOLO: deep links unavailable: $error');
    }
  }

  void _open(DeepLink link) {
    if (_hasSession) {
      _router.go(link.path);
      return;
    }
    // Signed out. Remember where they were going, then send them to sign-in:
    // the redirect below would otherwise make the link dead on arrival.
    _pending = link;
    _router.go(link.requiresSession ? '/welcome' : link.path);
  }

  bool get _hasSession => ref.read(sessionProvider).value != null;

  @override
  void dispose() {
    _linkSubscription?.cancel();
    super.dispose();
  }

  GoRouter _buildRouter() {
    return GoRouter(
      initialLocation: widget.initialLocation ?? '/',
      // A single redirect decides signed-in vs signed-out. Screens never each
      // re-check auth, which is how guard logic drifts out of sync.
      redirect: (context, state) {
        final session = ref.read(sessionProvider);
        final path = state.uri.path;
        final onAuthPath = path.startsWith('/welcome') ||
            path.startsWith('/login') ||
            path.startsWith('/register') ||
            path.startsWith('/verify');

        final user = session.value;
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
        // The signed-in frame. Each destination is a branch with its own
        // navigator, so switching tabs preserves scroll position and back
        // gestures behave the way people expect.
        StatefulShellRoute.indexedStack(
          builder: (context, state, navigationShell) =>
              KoloShell(navigationShell: navigationShell),
          branches: [
            StatefulShellBranch(
              routes: [GoRoute(path: '/', builder: (_, __) => const HomeScreen())],
            ),
            StatefulShellBranch(
              routes: [GoRoute(path: '/groups', builder: (_, __) => const GroupsTab())],
            ),
            StatefulShellBranch(
              routes: [GoRoute(path: '/messages', builder: (_, __) => const MessagesScreen())],
            ),
            StatefulShellBranch(
              routes: [GoRoute(path: '/account', builder: (_, __) => const ProfileScreen())],
            ),
          ],
        ),
        GoRoute(
          path: '/money',
          builder: (_, __) => const ContributionsScreen(),
        ),
        GoRoute(
          path: '/groups/new',
          builder: (_, __) => const CreateGroupScreen(),
        ),
        GoRoute(
          path: '/groups/join',
          builder: (_, state) => JoinGroupScreen(
            invitationCode: state.uri.queryParameters['code'],
          ),
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
        GoRoute(path: '/contributions', builder: (_, __) => const ContributionsScreen()),
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
      // A link that arrived while signed out is finally actionable.
      final pending = _pending;
      if (pending != null && next.hasValue && next.value != null) {
        _pending = null;
        WidgetsBinding.instance.addPostFrameCallback((_) => _router.go(pending.path));
        return;
      }
      if (next.hasValue && next.value == null) {
        final location = _router.routerDelegate.currentConfiguration.uri.path;
        if (!location.startsWith('/welcome') && !location.startsWith('/login')) {
          _router.go('/welcome');
        }
      }
    });


    return MaterialApp.router(
      title: 'KOLO',
      debugShowCheckedModeBanner: false,
      theme: KoloTheme.light(),
      routerConfig: _router,
    );
  }
}

/// Bridges a Riverpod provider to GoRouter's refresh mechanism.
///
/// A StatefulWidget's `ref` is a `WidgetRef`, which cannot outlive the widget, so
/// the notifier keeps the subscription and disposes it with itself.
class _ProviderNotifier extends ChangeNotifier {
  /// The provider is named concretely rather than through `ProviderListenable`.
  ///
  /// Two reasons, both from Riverpod 3: `ProviderListenable` is no longer
  /// exported from the default entrypoint, and `ProviderSubscription` is now
  /// parameterised by the provider's own state type, so the old
  /// `ProviderSubscription<AsyncValue<dynamic>>` no longer matched a
  /// subscription to `AsyncValue<UserProfile?>`. `FutureProvider` is exported by
  /// both 2.x and 3.x, so naming it needs no compatibility shim.
  _ProviderNotifier(WidgetRef ref, FutureProvider<UserProfile?> provider) {
    // `listen` on a WidgetRef returns void; `listenManual` gives us a
    // subscription we own and can cancel when the router is rebuilt.
    _subscription = ref.listenManual<AsyncValue<UserProfile?>>(
      provider,
      (_, __) => notifyListeners(),
    );
  }

  ProviderSubscription<AsyncValue<UserProfile?>>? _subscription;

  @override
  void dispose() {
    _subscription?.close();
    super.dispose();
  }
}

