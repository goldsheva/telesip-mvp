import 'package:app/state/auth/auth_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:app/services/auth_api.dart';
import 'package:app/services/auth_tokens_storage.dart';
import 'package:app/services/api_client.dart';

final secureStorageProvider = Provider<FlutterSecureStorage>((ref) {
  return const FlutterSecureStorage();
});

final authTokensStorageProvider = Provider<AuthTokensStorage>((ref) {
  return AuthTokensStorage(ref.read(secureStorageProvider));
});

final authApiProvider = Provider<AuthApi>((ref) {
  final api = AuthApi();
  ref.onDispose(api.dispose);
  return api;
});

final apiClientProvider = Provider<ApiClient>((ref) {
  final storage = ref.read(authTokensStorageProvider);
  final authApi = ref.read(authApiProvider);

  final client = ApiClient(
    readTokens: storage.readTokens,
    writeTokens: storage.writeTokens,
    clearTokens: storage.clear,
    refresh: (refresh) => authApi.refreshToken(refreshToken: refresh),
    onAuthLost: () => ref.read(authControllerProvider.notifier).logout(),
  );

  ref.onDispose(client.dispose);
  return client;
});
