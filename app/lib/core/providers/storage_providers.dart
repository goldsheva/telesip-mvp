import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:app/features/auth/data/auth_api.dart';
import 'package:app/core/storage/auth_tokens_storage.dart';
import 'package:app/core/storage/biometric_tokens_storage.dart';
import 'package:app/core/storage/general_sip_credentials_storage.dart';

final secureStorageProvider = Provider<FlutterSecureStorage>((ref) {
  return const FlutterSecureStorage();
});

final authTokensStorageProvider = Provider<AuthTokensStorage>((ref) {
  return AuthTokensStorage(ref.read(secureStorageProvider));
});

final biometricTokensStorageProvider = Provider<BiometricTokensStorage>((ref) {
  return BiometricTokensStorage(ref.read(secureStorageProvider));
});

final generalSipCredentialsStorageProvider =
    Provider<GeneralSipCredentialsStorage>((ref) {
      return GeneralSipCredentialsStorage(ref.read(secureStorageProvider));
    });

final authApiProvider = Provider<AuthApi>((ref) {
  final api = AuthApi();
  ref.onDispose(api.dispose);
  return api;
});
