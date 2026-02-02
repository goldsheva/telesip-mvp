import 'package:app/models/auth_tokens.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AuthTokensStorage {
  const AuthTokensStorage(this._storage);

  final FlutterSecureStorage _storage;

  static const _keyAccess = 'access_token';
  static const _keyRefresh = 'refresh_token';

  Future<AuthTokens?> readTokens() async {
    final access = await _storage.read(key: _keyAccess);
    final refresh = await _storage.read(key: _keyRefresh);

    if (access == null || refresh == null || access.isEmpty || refresh.isEmpty) {
      return null;
    }

    return AuthTokens(accessToken: access, refreshToken: refresh);
  }

  Future<void> writeTokens(AuthTokens t) async {
    await _storage.write(key: _keyAccess, value: t.accessToken);
    await _storage.write(key: _keyRefresh, value: t.refreshToken);
  }

  Future<void> clear() async {
    await _storage.delete(key: _keyAccess);
    await _storage.delete(key: _keyRefresh);
  }
}
