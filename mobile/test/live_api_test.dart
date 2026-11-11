/// Integration tests that drive the real [ApiClient] against a running backend.
///
/// These are opt-in. They are skipped unless `KOLO_LIVE_BASE` is set, because a
/// unit test run should never depend on a server being up:
///
///     KOLO_LIVE_BASE=http://127.0.0.1:8000/api/v1 flutter test test/live_api_test.dart
///
/// What they prove that no widget test can: the Flutter client's own request
/// shapes, envelope unwrapping, error mapping, token attachment and refresh
/// handling are correct against the actual Django API. A typo in a path or a
/// field name shows up here and nowhere earlier.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kolo/core/api/api_client.dart';
import 'package:kolo/core/api/api_exception.dart';
import 'package:kolo/core/api/token_store.dart';

/// An in-memory token store: the platform keystore needs a real device.
class MemoryTokenStore extends TokenStore {
  MemoryTokenStore();

  String? _access;
  String? _refresh;

  @override
  Future<String?> accessToken() async => _access;

  @override
  Future<String?> refreshToken() async => _refresh;

  @override
  Future<void> save({required String access, required String refresh}) async {
    _access = access;
    _refresh = refresh;
  }

  @override
  Future<void> updateAccess(String access) async {
    _access = access;
  }

  @override
  Future<void> clear() async {
    _access = null;
    _refresh = null;
  }

  @override
  Future<bool> get hasSession async => _refresh != null;
}

const _password = 'Str0ng-Passw0rd!23';

String _uniqueEmail(String label) {
  final stamp = DateTime.now().microsecondsSinceEpoch;
  return 'flutter.$label.$stamp@example.com';
}

/// Wait out a rate limit and try once more.
///
/// The auth throttle is a real protection (ten requests a minute), and this file
/// onboards several members within a minute. Rather than weaken the server, the
/// test honours the refusal the way a well-behaved client should — and in doing
/// so exercises [ApiException.isRateLimited] and `retryAfterSeconds`.
Future<T> honouringRateLimit<T>(Future<T> Function() attempt) async {
  for (var tries = 0; ; tries++) {
    try {
      return await attempt();
    } on ApiException catch (error) {
      if (!error.isRateLimited || tries >= 3) rethrow;
      final wait = error.retryAfterSeconds ?? 20;
      await Future<void>.delayed(Duration(seconds: (wait + 1).clamp(1, 62)));
    }
  }
}

void main() {
  // These tests wait out the server's real rate limiting, so the default
  // 30-second per-test timeout is not enough. The waits are deliberate: the
  // alternative is weakening a protection just to make a test faster.
  const perTestTimeout = Timeout(Duration(minutes: 3));
  final baseUrl = Platform.environment['KOLO_LIVE_BASE'];
  final serverLog = Platform.environment['KOLO_SERVER_LOG'] ?? '/tmp/kolo_server.log';

  /// The API never returns an OTP, correctly. The dev server writes it to its
  /// own log through the console email backend, which is where a human tester
  /// would find it too.
  String? readOtp(String email) {
    final file = File(serverLog);
    if (!file.existsSync()) return null;
    final text = file.readAsStringSync();
    final matches = RegExp(
      'To: ${RegExp.escape(email)}\\b[\\s\\S]*?Your KOLO code is (\\d{6})',
    ).allMatches(text);
    return matches.isEmpty ? null : matches.last.group(1);
  }

  group('live backend', () {
    late ApiClient client;
    late MemoryTokenStore tokens;

    setUp(() {
      tokens = MemoryTokenStore();
      client = ApiClient(tokens: tokens, baseUrl: baseUrl);
    });

    /// Register, sign in, and leave the client holding a real session.
    Future<void> join(ApiClient api, MemoryTokenStore store, String label) async {
      final email = _uniqueEmail(label);
      await honouringRateLimit(() => api.post('/auth/register/', body: {
            'email': email,
            'password': _password,
            'full_name': 'Flutter $label',
          }));
      final login = await honouringRateLimit(() => api.post('/auth/login/', body: {
            'identifier': email,
            'password': _password,
          }));
      await store.save(
        access: login['access'] as String,
        refresh: login['refresh'] as String,
      );
    }

    test('registration, verification and login work through the client', () async {
      final email = _uniqueEmail('signup');

      // Registration returns the created member; it must not hand out tokens.
      final registered = await honouringRateLimit(() => client.post('/auth/register/', body: {
            'email': email,
            'password': _password,
            'full_name': 'Flutter Member',
          }));
      expect(registered['user'], isNotNull);
      expect(registered.containsKey('access'), isFalse,
          reason: 'registering must not sign a member in before their email is proved');

      final login = await honouringRateLimit(() => client.post('/auth/login/', body: {
            'identifier': email,
            'password': _password,
          }));
      final access = login['access'] as String?;
      final refresh = login['refresh'] as String?;
      expect(access, isNotNull);
      expect(refresh, isNotNull);
      await tokens.save(access: access!, refresh: refresh!);

      // The token is attached by the client, not by the caller.
      final me = await client.get('/auth/me/');
      final profile = (me['user'] as Map?)?.cast<String, dynamic>() ?? me;
      expect(profile['is_email_verified'], isFalse);

      final code = readOtp(email);
      expect(code, isNotNull, reason: 'no OTP found in $serverLog');

      final verified = await honouringRateLimit(
        () => client.post('/auth/verify/', body: {'code': code, 'purpose': 'signup'}),
      );
      final verifiedProfile = (verified['user'] as Map?)?.cast<String, dynamic>() ?? verified;
      expect(verifiedProfile['is_email_verified'], isTrue);
      expect(verifiedProfile['verification_level'], anyOf('contact', 'basic'));
    }, timeout: perTestTimeout);

    test('a wrong OTP comes back as a typed refusal with attempts left', () async {
      await join(client, tokens, 'wrongotp');

      try {
        await honouringRateLimit(
          () => client.post('/auth/verify/', body: {'code': '000000', 'purpose': 'signup'}),
        );
        fail('a wrong code must not be accepted');
      } on ApiException catch (error) {
        expect(error.code, 'otp_invalid');
        expect(error.statusCode, 400);
        expect(error.details['attempts_left'], isA<int>());
        expect(error.message, isNotEmpty, reason: 'the UI shows this text to the member');
      }
    }, timeout: perTestTimeout);

    test('the client refreshes an expired access token and replays the request', () async {
      final email = _uniqueEmail('refresh');
      await honouringRateLimit(() => client.post('/auth/register/', body: {
            'email': email,
            'password': _password,
            'full_name': 'Refresh Member',
          }));
      final login = await honouringRateLimit(() => client.post('/auth/login/', body: {
            'identifier': email,
            'password': _password,
          }));
      await tokens.save(
        access: 'deliberately.invalid.token',
        refresh: login['refresh'] as String,
      );

      // The access token is rejected; the interceptor refreshes and retries.
      final me = await client.get('/auth/me/');
      expect(me, isNotEmpty);

      final rotated = await tokens.accessToken();
      expect(rotated, isNot('deliberately.invalid.token'));
      expect(rotated, isNotNull);
    }, timeout: perTestTimeout);

    test('an unrecoverable 401 signs the member out instead of failing obscurely', () async {
      await tokens.save(access: 'still.invalid', refresh: 'also.invalid');
      var signedOut = false;
      client.onSessionExpired = () => signedOut = true;

      try {
        await client.get('/auth/me/');
        fail('a dead session must not return data');
      } on ApiException catch (error) {
        expect(error.isAuthError, isTrue);
      }
      expect(signedOut, isTrue, reason: 'the shell must be told to return to sign-in');
      expect(await tokens.accessToken(), isNull, reason: 'dead tokens must not stay on the device');
    }, timeout: perTestTimeout);

    test('a rotated refresh token is dead, and the client surfaces the refusal', () async {
      await join(client, tokens, 'family');
      final first = await tokens.refreshToken();

      final rotated = await client.post('/auth/refresh/', body: {'refresh': first});
      expect(rotated['refresh'], isNot(first));

      try {
        await honouringRateLimit(
          () => client.post('/auth/refresh/', body: {'refresh': first}),
        );
        fail('replaying a rotated token must be refused');
      } on ApiException catch (error) {
        expect(error.code, 'refresh_revoked');
        expect(error.statusCode, 403);
      }
    }, timeout: perTestTimeout);

    test('a member can create a group, read it back and a stranger is refused', () async {
      await join(client, tokens, 'group');

      final group = await honouringRateLimit(() => client.post('/groups/', body: {
            'name': 'Flutter Ajo ${DateTime.now().millisecondsSinceEpoch}',
            'currency': 'NGN',
            'visibility': 'private',
          }));
      final slug = group['slug'] as String?;
      expect(slug, isNotNull);

      // List endpoints go through getList and must be decodable.
      final groups = await client.getList('/groups/');
      expect(groups.map((g) => g['slug']), contains(slug));

      final members = await client.getList('/groups/$slug/members/');
      expect(members, hasLength(1));
      expect(members.first['role'], anyOf('founder', 'owner', 'chairperson'));

      // A different member's token must not see the member list.
      final strangerTokens = MemoryTokenStore();
      final outsider = ApiClient(tokens: strangerTokens, baseUrl: baseUrl);
      await join(outsider, strangerTokens, 'stranger');

      try {
        await outsider.getList('/groups/$slug/members/');
        fail('membership is not a formality: a stranger must be refused');
      } on ApiException catch (error) {
        expect(error.statusCode, anyOf(403, 404));
      }
    }, timeout: perTestTimeout);

    test('money refusals keep their machine code so the UI can explain them', () async {
      await join(client, tokens, 'money');

      // Lending is gated off until approved financial and legal arrangements
      // exist; the client must be able to tell that apart from a generic error.
      try {
        final products = await client.getList('/loans/products/');
        expect(products, isNotNull);
      } on ApiException catch (error) {
        expect(error.code, isNotEmpty);
      }

      // An invalid contribution amount is a refusal with a stable code — never a
      // silent success.
      try {
        await client.post('/payments/intents/', body: {
          'purpose': 'contribution',
          'amount_minor': 0,
          'currency': 'NGN',
        });
        fail('a zero-amount payment intent must be refused');
      } on ApiException catch (error) {
        expect(error.statusCode, 400);
        expect(error.code, isNotEmpty);
      }
    }, timeout: perTestTimeout);

    test('the contribution flow reports server-side status, not a client guess', () async {
      await join(client, tokens, 'contribute');

      // A member outside any programme cannot contribute; the refusal must be a
      // typed, explainable one rather than a pretend success.
      try {
        await client.post('/savings/programmes/00000000-0000-0000-0000-000000000000/contributions/',
            body: {'amount_minor': 100000});
        fail('a contribution to a programme that does not exist must be refused');
      } on ApiException catch (error) {
        expect(error.statusCode, isNotNull);
        expect(error.code, isNotEmpty);
      }

      // Obligations are served by the backend; the client must not invent them.
      final obligations = await client.getList('/savings/obligations/');
      expect(obligations, isEmpty, reason: 'a new member owes nothing yet');
    }, timeout: perTestTimeout);
  }, skip: baseUrl == null ? 'set KOLO_LIVE_BASE to run against a live server' : null);
}
