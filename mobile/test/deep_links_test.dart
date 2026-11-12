import 'package:flutter_test/flutter_test.dart';
import 'package:kolo/core/deeplink/deep_links.dart';

/// A deep link chooses a screen. It never grants anything: the server still
/// decides what this member may see, and every destination below shows that
/// refusal rather than pretending the link was the authorisation.
void main() {
  group('links that belong to KOLO', () {
    test('a group link opens the group', () {
      expect(DeepLink.parse(Uri.parse('kolo://app/groups/ajo-ilorin')), 
          const DeepLink(path: '/groups/ajo-ilorin'));
      expect(DeepLink.parse(Uri.parse('https://kolo.app/groups/ajo-ilorin')),
          const DeepLink(path: '/groups/ajo-ilorin'));
    });

    test('a chat link opens the conversation, not the group behind it', () {
      expect(DeepLink.parse(Uri.parse('kolo://app/groups/ajo-ilorin/chat')),
          const DeepLink(path: '/groups/ajo-ilorin/chat'));
    });

    test('a programme link opens the programme', () {
      expect(
        DeepLink.parse(Uri.parse('kolo://app/programmes/p-123')),
        const DeepLink(path: '/programmes/p-123'),
      );
    });

    test('an invitation survives being opened by somebody with no account', () {
      final link = DeepLink.parse(Uri.parse('kolo://app/invite/abc123'));

      expect(link, isNotNull);
      expect(link!.path, '/groups/join?code=abc123');
      expect(link.requiresSession, isFalse,
          reason: 'the person tapping an invitation usually has not signed up yet');
    });

    test('an invitation token is carried through and escaped', () {
      final link = DeepLink.parse(Uri.parse('https://kolo.app/invite/a%20b%26c'));

      // `+` is the correct encoding for a space in a query component, and the
      // `&` must survive as data rather than starting a new parameter.
      expect(link!.path, '/groups/join?code=a+b%26c');
      expect(Uri.parse('kolo://app${link.path}').queryParameters['code'], 'a b&c');
    });

    test('an invitation with no token still lands somewhere useful', () {
      expect(
        DeepLink.parse(Uri.parse('kolo://app/invite')),
        const DeepLink(path: '/groups/join'),
      );
    });

    test('a payment link opens contributions and carries no amount', () {
      // The amount is deliberately discarded: a URL must never decide how much
      // money leaves an account.
      final link = DeepLink.parse(Uri.parse('kolo://app/pay?amount=999999'));

      expect(link!.path, '/contributions');
      expect(link.path.contains('999999'), isFalse);
    });

    test('a verification link carries the address to verify', () {
      final link = DeepLink.parse(Uri.parse('kolo://app/verify?email=member@example.com'));

      expect(link!.path, '/verify?email=member%40example.com');
      expect(link.requiresSession, isFalse);
    });
  });

  group('links that are not ours, or are broken', () {
    test('another app\'s custom scheme is ignored', () {
      expect(DeepLink.parse(Uri.parse('evil://app/groups/x')), isNull);
    });

    test('another site on https is ignored', () {
      expect(DeepLink.parse(Uri.parse('https://not-kolo.example/groups/x')), isNull);
    });

    test('plain http is not accepted for our domain', () {
      // Downgrading the scheme would let a network attacker choose the screen.
      expect(DeepLink.parse(Uri.parse('http://kolo.app/groups/x')), isNull);
    });

    test('an unknown path goes home rather than to a dead screen', () {
      expect(DeepLink.parse(Uri.parse('kolo://app/nonsense')), const DeepLink(path: '/'));
    });

    test('a half-written link does not crash', () {
      expect(DeepLink.parse(Uri.parse('kolo://app/groups')), const DeepLink(path: '/'));
      expect(DeepLink.parse(Uri.parse('kolo://app/programmes')), const DeepLink(path: '/'));
      expect(DeepLink.parse(Uri.parse('kolo://app')), const DeepLink(path: '/'));
    });
  });
}
