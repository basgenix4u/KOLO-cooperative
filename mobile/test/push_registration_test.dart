import 'package:flutter_test/flutter_test.dart';
import 'package:kolo/core/api/api_exception.dart';
import 'package:kolo/core/notifications/push_registration.dart';

/// Push is how an officer learns a payout is waiting for their signature. The
/// failure that matters is not "no notification" — it is claiming a notification
/// will arrive when nothing was registered.
class _FakeClient extends ApiClientLike {
  _FakeClient({this.throws});

  final Object? throws;
  final Map<String, Object?> calls = {};

  @override
  Future<Map<String, dynamic>> post(String path, {Object? body, String? idempotencyKey}) async {
    calls[path] = body;
    if (throws != null) throw throws!;
    return const {'registered': true};
  }
}

void main() {
  test('a token is sent with the device id and reported as registered', () async {
    final client = _FakeClient();
    final push = PushRegistration(client)..rememberToken('fcm-123');

    final outcome = await push.register(deviceId: 'device-abc');

    expect(outcome, PushOutcome.registered);
    expect(client.calls['/auth/push-token/'], {
      'device_id': 'device-abc',
      'push_token': 'fcm-123',
    });
  });

  test('no token means unavailable, and nothing is sent', () async {
    // The ordinary case in a build without google-services.json. It must not
    // look like success, and it must not be an error the member has to see.
    final client = _FakeClient();
    final push = PushRegistration(client);

    expect(await push.register(deviceId: 'device-abc'), PushOutcome.unavailable);
    expect(client.calls, isEmpty);
  });

  test('no device session means no attempt', () async {
    final client = _FakeClient();
    final push = PushRegistration(client)..rememberToken('fcm-123');

    expect(await push.register(deviceId: ''), PushOutcome.noDevice);
    expect(client.calls, isEmpty);
  });

  test('a device the server does not recognise is reported as such', () async {
    // After a reinstall the stored device id is stale. The member has to sign in
    // again before notifications can work, and that has to be knowable.
    final client = _FakeClient(
      throws: ApiException(code: 'device_not_found', message: 'gone'),
    );
    final push = PushRegistration(client)..rememberToken('fcm-123');

    expect(await push.register(deviceId: 'stale'), PushOutcome.deviceUnknown);
  });

  test('any other failure is not reported as registered', () async {
    final client = _FakeClient(throws: ApiException(code: 'server_error', message: 'boom'));
    final push = PushRegistration(client)..rememberToken('fcm-123');

    expect(await push.register(deviceId: 'device-abc'), PushOutcome.failed);
  });

  test('the quiet path never throws, whatever happens', () async {
    final client = _FakeClient(throws: ApiException(code: 'server_error', message: 'boom'));
    final push = PushRegistration(client)..rememberToken('fcm-123');

    await push.registerQuietly(deviceId: 'device-abc');
  });
}
