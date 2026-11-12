import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Tokens live in the platform keystore, never in shared preferences.
///
/// Shared preferences is plain text on disk. A refresh token in it is a
/// long-lived credential sitting in a file that any backup or rooted device can
/// read, so the two are kept separate and only this class touches the secure one.
class TokenStore {
  TokenStore({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
              iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
            );

  final FlutterSecureStorage _storage;

  static const _accessKey = 'kolo.access_token';
  static const _refreshKey = 'kolo.refresh_token';

  /// The server's id for this sign-in. Push notifications are addressed to a
  /// device session, so without this there is nothing to attach a token to and
  /// no way to tell the server which install to notify.
  static const _deviceKey = 'kolo.device_id';

  String? _cachedAccess;
  String? _cachedRefresh;
  String? _cachedDevice;

  Future<String?> deviceId() async {
    _cachedDevice ??= await _storage.read(key: _deviceKey);
    return _cachedDevice;
  }

  Future<void> saveDeviceId(String deviceId) async {
    if (deviceId.isEmpty) return;
    _cachedDevice = deviceId;
    await _storage.write(key: _deviceKey, value: deviceId);
  }

  Future<String?> accessToken() async {
    _cachedAccess ??= await _storage.read(key: _accessKey);
    return _cachedAccess;
  }

  Future<String?> refreshToken() async {
    _cachedRefresh ??= await _storage.read(key: _refreshKey);
    return _cachedRefresh;
  }

  Future<void> save({
    required String access,
    required String refresh,
    String deviceId = '',
  }) async {
    _cachedAccess = access;
    _cachedRefresh = refresh;
    await _storage.write(key: _accessKey, value: access);
    await _storage.write(key: _refreshKey, value: refresh);
    if (deviceId.isNotEmpty) await saveDeviceId(deviceId);
  }

  Future<void> updateAccess(String access) async {
    _cachedAccess = access;
    await _storage.write(key: _accessKey, value: access);
  }

  Future<void> clear() async {
    _cachedAccess = null;
    _cachedRefresh = null;
    _cachedDevice = null;
    await _storage.delete(key: _accessKey);
    await _storage.delete(key: _refreshKey);
  }

  Future<bool> get hasSession async => (await refreshToken()) != null;
}
