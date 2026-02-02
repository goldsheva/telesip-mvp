
import 'package:app/models/auth_tokens.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AuthTokensStorage {
  const AuthTokensStorage(this._flutterSecureStorage);

  final FlutterSecureStorage _flutterSecureStorage;

  static const _keyAccess = 'access_token';
  static const _keyRefresh = 'refresh_token';

  Future<AuthTokens?> readTokens() async {
    final accessToken = await _flutterSecureStorage.read(key: _keyAccess);
    final refreshToken = await _flutterSecureStorage.read(key: _keyRefresh);
    if (accessToken == null || refreshToken == null || accessToken.isEmpty || refreshToken.isEmpty) {
      return null;
    }
    return AuthTokens(accessToken: accessToken, refreshToken: refreshToken);
  }

  Future<String?> readAccessToken() => _flutterSecureStorage.read(key: _keyAccess);
  Future<String?> readRefreshToken() => _flutterSecureStorage.read(key: _keyRefresh);

  Future<void> writeTokens(AuthTokens t) async {
    await _flutterSecureStorage.write(key: _keyAccess, value: t.accessToken);
    await _flutterSecureStorage.write(key: _keyRefresh, value: t.refreshToken);
  }

  Future<void> clear() async {
    await _flutterSecureStorage.delete(key: _keyAccess);
    await _flutterSecureStorage.delete(key: _keyRefresh);
  }
}
