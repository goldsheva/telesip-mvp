import 'package:app/features/auth/models/auth_tokens.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class BiometricTokensStorage {
  const BiometricTokensStorage(this._storage);

  final FlutterSecureStorage _storage;

  static const _keyAccess = 'biometric_access_token';
  static const _keyRefresh = 'biometric_refresh_token';

  Future<AuthTokens?> readTokens() async {
    final access = await _storage.read(key: _keyAccess);
    final refresh = await _storage.read(key: _keyRefresh);

    if (access == null ||
        refresh == null ||
        access.isEmpty ||
        refresh.isEmpty) {
      return null;
    }

    return AuthTokens(accessToken: access, refreshToken: refresh);
  }

  Future<void> writeTokens(AuthTokens t) async {
    await _storage.write(key: _keyAccess, value: t.accessToken);
    await _storage.write(key: _keyRefresh, value: t.refreshToken);
  }
}
