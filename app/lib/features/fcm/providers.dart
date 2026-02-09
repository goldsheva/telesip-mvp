import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:app/core/providers/network_providers.dart';
import 'package:app/core/providers/storage_providers.dart';
import 'package:app/core/storage/auth_tokens_storage.dart';
import 'package:app/core/storage/fcm_storage.dart';
import 'package:app/features/fcm/data/fcm_token_api.dart';

final fcmTokenApiProvider = Provider<FcmTokenApi>((ref) {
  return FcmTokenApi(ref.read(apiClientProvider));
});

final fcmTokenRegistrarProvider = Provider<FcmTokenRegistrar>((ref) {
  return FcmTokenRegistrar(
    api: ref.read(fcmTokenApiProvider),
    authTokensStorage: ref.read(authTokensStorageProvider),
  );
});

class FcmTokenRegistrar {
  FcmTokenRegistrar({
    required FcmTokenApi api,
    required AuthTokensStorage authTokensStorage,
  }) : _api = api,
       _authTokensStorage = authTokensStorage;

  final FcmTokenApi _api;
  final AuthTokensStorage _authTokensStorage;

  Future<void> register(String token) async {
    final tokens = await _authTokensStorage.readTokens();
    if (tokens == null) return;

    try {
      await _api.registerToken(token: token);
    } catch (error) {
      debugPrint('Unable to register FCM token: $error');
    }
  }

  Future<void> registerStoredToken() async {
    final token = await FcmStorage.readToken();
    if (token == null || token.isEmpty) return;
    await register(token);
  }
}
