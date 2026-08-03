import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class TokenStorage {
  TokenStorage({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _accessTokenKey = 'api_access_token';
  static const _geolocationRequiredKey = 'api_geolocation_required';
  static const _deviceValidationRequiredKey = 'api_device_validation_required';

  final FlutterSecureStorage _storage;

  Future<String?> readAccessToken() => _storage.read(key: _accessTokenKey);

  Future<void> saveAccessToken(String token) {
    return _storage.write(key: _accessTokenKey, value: token);
  }

  Future<void> saveApiSession({
    required String accessToken,
    required bool geolocationRequired,
    required bool deviceValidationRequired,
  }) async {
    await _storage.write(key: _accessTokenKey, value: accessToken);
    await _storage.write(
      key: _geolocationRequiredKey,
      value: geolocationRequired.toString(),
    );
    await _storage.write(
      key: _deviceValidationRequiredKey,
      value: deviceValidationRequired.toString(),
    );
  }

  Future<bool> readGeolocationRequired() async {
    final value = await _storage.read(key: _geolocationRequiredKey);
    return value?.toLowerCase() == 'false' ? false : true;
  }

  Future<bool> readDeviceValidationRequired() async {
    final value = await _storage.read(key: _deviceValidationRequiredKey);
    return value?.toLowerCase() == 'false' ? false : true;
  }

  Future<void> clearAccessToken() async {
    await _storage.delete(key: _accessTokenKey);
    await _storage.delete(key: _geolocationRequiredKey);
    await _storage.delete(key: _deviceValidationRequiredKey);
  }
}
