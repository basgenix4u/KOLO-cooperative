import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_exception.dart';
import '../../core/api/providers.dart';
import '../../core/api/token_store.dart';
import '../../core/models/models.dart';

/// The signed-in member, or null.
///
/// Modelled as an [AsyncValue] so every screen gets loading and error states for
/// free rather than each one inventing its own booleans.
final sessionProvider = FutureProvider<UserProfile?>((ref) async {
  final client = ref.watch(apiClientProvider);
  final tokens = ref.watch(tokenStoreProvider);
  if (!await tokens.hasSession) return null;

  try {
    final data = await client.get('/auth/me/');
    final user = data['user'];
    if (user is Map<String, dynamic>) return UserProfile.fromJson(user);
    return UserProfile.fromJson(data);
  } on ApiException catch (error) {
    if (error.isAuthError) return null;
    rethrow;
  }
});

class AuthController {
  AuthController(this._ref);

  final Ref _ref;

  ApiClient get _client => _ref.read(apiClientProvider);
  TokenStore get _tokens => _ref.read(tokenStoreProvider);

  Future<void> register({
    required String email,
    required String password,
    required String fullName,
  }) async {
    await _client.post('/auth/register/', body: {
      'email': email.trim().toLowerCase(),
      'password': password,
      'full_name': fullName.trim(),
    });
  }

  Future<UserProfile> login({required String identifier, required String password}) async {
    final data = await _client.post('/auth/login/', body: {
      'identifier': identifier.trim(),
      'password': password,
    });

    final access = data['access'] as String?;
    final refresh = data['refresh'] as String?;
    if (access == null || refresh == null) {
      throw ApiException(
        code: 'invalid_response',
        message: 'Sign-in did not return a session. Please try again.',
      );
    }
    await _tokens.save(
      access: access,
      refresh: refresh,
      // Kept so a push token can be attached to this session later.
      deviceId: '${data['device_id'] ?? ''}',
    );
    _ref.invalidate(sessionProvider);

    final user = data['user'];
    if (user is Map<String, dynamic>) return UserProfile.fromJson(user);
    final me = await _client.get('/auth/me/');
    return UserProfile.fromJson((me['user'] as Map?)?.cast<String, dynamic>() ?? me);
  }

  /// Confirms an emailed or texted code. Requires an access token, which is why
  /// registration does not sign the member in: proving the address is the point.
  Future<void> verifyCode({required String code, String purpose = 'signup'}) async {
    await _client.post('/auth/verify/', body: {'code': code.trim(), 'purpose': purpose});
    _ref.invalidate(sessionProvider);
  }

  Future<void> requestCode({required String channel, String purpose = 'signup'}) async {
    await _client.post('/auth/resend/', body: {'channel': channel, 'purpose': purpose});
  }

  Future<void> logout() async {
    try {
      await _client.post('/auth/logout/', body: {'all_devices': false});
    } on ApiException {
      // A failed logout call must still clear the device: the member asked to
      // be signed out, and refusing would leave tokens on the phone.
    }
    await _tokens.clear();
    _ref.invalidate(sessionProvider);
  }
}

final authControllerProvider = Provider<AuthController>((ref) => AuthController(ref));
