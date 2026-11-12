import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/providers.dart';

/// Registering this device for push notifications.
///
/// The backend already delivers over FCM; what was missing was the client half.
/// Two things matter more than the plumbing:
///
///  * **A missing Firebase configuration is a normal state, not a failure.** The
///    app must run, and say nothing untrue, in a build with no
///    `google-services.json`. Push is then simply off, exactly as the backend
///    behaves without FCM credentials.
///  * **A token is only useful if the server accepted it.** The registration
///    call reports what the server said rather than assuming success; a stale
///    device session has to be visible, because an officer who receives no
///    notification cannot approve a payout.
/// The one call this file needs, so the logic can be tested without a network
/// stack or a platform channel.
abstract class ApiClientLike {
  Future<Map<String, dynamic>> post(String path, {Object? body, String? idempotencyKey});
}

class PushRegistration {
  PushRegistration(this._client);

  final ApiClientLike _client;

  /// Set by the platform layer once a token is available. Kept as a plain
  /// string so the rest of the app never depends on the Firebase SDK, and so
  /// this file can be tested without it.
  String _token = '';

  String get token => _token;

  void rememberToken(String token) {
    _token = token;
  }

  /// Send the token for an existing device session.
  ///
  /// Returns true only when the server confirmed it stored the token. A 404
  /// means the session is gone — the member was signed out elsewhere, or the app
  /// was reinstalled — and the caller should sign in again rather than assume
  /// notifications will arrive.
  Future<PushOutcome> register({required String deviceId}) async {
    if (_token.isEmpty) return PushOutcome.unavailable;
    if (deviceId.isEmpty) return PushOutcome.noDevice;

    try {
      await _client.post('/auth/push-token/', body: {
        'device_id': deviceId,
        'push_token': _token,
      });
      return PushOutcome.registered;
    } on Object catch (error) {
      final text = error.toString().toLowerCase();
      if (text.contains('device_not_found') || text.contains('404')) {
        return PushOutcome.deviceUnknown;
      }
      return PushOutcome.failed;
    }
  }

  /// Called after sign-in, when there is finally a session to attach a token to.
  ///
  /// Deliberately quiet: nobody should see an error because push is off. What
  /// must not happen is a silent claim of success, which is why the outcome is
  /// reported to the caller and logged.
  Future<void> registerQuietly({required String deviceId}) async {
    final outcome = await register(deviceId: deviceId);
    if (outcome != PushOutcome.registered) {
      debugPrint('KOLO: push not registered (${outcome.name})');
    }
  }
}

enum PushOutcome {
  /// The server stored the token.
  registered,

  /// No token yet: no Firebase configuration, or the platform has not supplied
  /// one. Not an error, and must never be reported as success.
  unavailable,

  /// No device session to attach it to.
  noDevice,

  /// The server does not recognise this device session.
  deviceUnknown,

  /// The request failed for another reason.
  failed,
}

final pushRegistrationProvider = Provider<PushRegistration>((ref) {
  // ApiClient satisfies ApiClientLike structurally; the cast keeps the provider
  // typed against the small interface rather than the whole HTTP client.
  return PushRegistration(ref.watch(apiClientProvider) as ApiClientLike);
});
