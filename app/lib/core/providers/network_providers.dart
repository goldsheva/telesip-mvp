import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:app/core/network/api_client.dart';
import 'package:app/features/auth/state/auth_notifier.dart';

import 'storage_providers.dart';

final apiClientProvider = Provider<ApiClient>((ref) {
  final storage = ref.read(authTokensStorageProvider);
  final authApi = ref.read(authApiProvider);

  final client = ApiClient(
    readTokens: storage.readTokens,
    writeTokens: storage.writeTokens,
    clearTokens: storage.clear,
    refresh: (refresh) => authApi.refreshToken(refreshToken: refresh),
    onAuthLost: () => ref.read(authNotifierProvider.notifier).logout(),
  );

  ref.onDispose(client.dispose);
  return client;
});
