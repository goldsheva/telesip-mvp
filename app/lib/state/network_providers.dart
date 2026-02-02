import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:app/services/api_client.dart';
import 'package:app/state/core_providers.dart';
import 'package:app/state/auth/auth_controller.dart';

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
