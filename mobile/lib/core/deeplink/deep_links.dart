import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';

/// Turning an incoming link into an in-app destination.
///
/// Kept as a pure function so the rules can be tested without a device, and so
/// the interesting decisions are readable in one place:
///
///  * a link never grants access. It chooses a screen; the server still decides
///    whether this member may see what is on it, and the screen shows the
///    refusal if not.
///  * anything unrecognised goes home rather than producing a dead screen. A
///    broken link is not an error worth showing a member.
///  * an invitation is the exception: it has to survive signing in, because the
///    person tapping it usually does not have an account yet.
class DeepLink {
  const DeepLink({required this.path, this.requiresSession = true});

  /// The route to open, using the app's own path scheme.
  final String path;

  /// False for links that a signed-out visitor must still be able to open.
  final bool requiresSession;

  @override
  String toString() => 'DeepLink($path, requiresSession: $requiresSession)';

  @override
  bool operator ==(Object other) =>
      other is DeepLink && other.path == path && other.requiresSession == requiresSession;

  @override
  int get hashCode => Object.hash(path, requiresSession);

  static const String scheme = 'kolo';
  static const String host = 'app';
  static const String webHost = 'kolo.app';

  /// The schemes and hosts this app answers to. A link from anywhere else is
  /// not ours and must not be acted on.
  static bool isOurs(Uri uri) {
    if (uri.scheme == scheme && (uri.host == host || uri.host.isEmpty)) return true;
    return uri.scheme == 'https' && uri.host == webHost;
  }

  /// Parse one link, or null when it is not ours to handle.
  static DeepLink? parse(Uri uri) {
    if (!isOurs(uri)) return null;

    // Both `kolo://app/groups/x` and `https://kolo.app/groups/x` reduce to the
    // same segments; the custom scheme carries "app" as its host, not as a path.
    final segments = [...uri.pathSegments.where((s) => s.isNotEmpty)];

    if (segments.isEmpty) return const DeepLink(path: '/');

    final first = segments.first;
    switch (first) {
      case 'invite':
      case 'invitations':
      case 'join':
        // The token identifies one invitation. It is passed as a query
        // parameter so the join screen receives it exactly as it would from a
        // typed code.
        final token = segments.length > 1 ? segments[1] : uri.queryParameters['token'];
        if (token == null || token.isEmpty) return const DeepLink(path: '/groups/join');
        return DeepLink(
          path: '/groups/join?code=${Uri.encodeQueryComponent(token)}',
          requiresSession: false,
        );

      case 'groups':
        if (segments.length < 2) return const DeepLink(path: '/');
        final slug = segments[1];
        if (segments.length >= 3 && segments[2] == 'chat') {
          return DeepLink(path: '/groups/${Uri.encodeComponent(slug)}/chat');
        }
        return DeepLink(path: '/groups/${Uri.encodeComponent(slug)}');

      case 'programmes':
        if (segments.length < 2) return const DeepLink(path: '/');
        final id = segments[1];
        if (segments.length >= 3 && segments[2] == 'payouts') {
          return DeepLink(path: '/programmes/${Uri.encodeComponent(id)}/payouts');
        }
        return DeepLink(path: '/programmes/${Uri.encodeComponent(id)}');

      case 'pay':
      case 'contribute':
        // A payment link opens the member's own contributions; the amount is
        // never taken from the link, because a URL is not a source of truth for
        // money. The member picks what they owe from the server's own figures.
        return const DeepLink(path: '/contributions');

      case 'verify':
        final email = uri.queryParameters['email'];
        if (email == null || email.isEmpty) return const DeepLink(path: '/welcome', requiresSession: false);
        return DeepLink(
          path: '/verify?email=${Uri.encodeQueryComponent(email)}',
          requiresSession: false,
        );

      default:
        return const DeepLink(path: '/');
    }
  }
}

/// Streams links while the app is running. Separated from [DeepLink] so the
/// parsing rules stay testable and this stays a thin, disposable wrapper.
class DeepLinkListener {
  DeepLinkListener({AppLinks? links}) : _links = links ?? AppLinks();

  final AppLinks _links;

  /// Links that arrived before anyone was listening. Cold starts deliver the
  /// link that launched the app exactly once, and missing it means an invitation
  /// silently does nothing.
  Future<DeepLink?> initial() async {
    try {
      final uri = await _links.getInitialLink();
      return uri == null ? null : DeepLink.parse(uri);
    } catch (error) {
      // A platform that cannot report the launch link is not a reason to fail
      // to start.
      debugPrint('KOLO: could not read the initial link: $error');
      return null;
    }
  }

  Stream<DeepLink> stream() {
    return _links.uriLinkStream
        .map(DeepLink.parse)
        .where((link) => link != null)
        .cast<DeepLink>();
  }
}
