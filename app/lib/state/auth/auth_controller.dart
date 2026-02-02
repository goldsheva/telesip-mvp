import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:app/state/core_providers.dart';
import 'package:app/state/dongles/dongles_providers.dart';
import 'auth_state.dart';

final authControllerProvider =
    AsyncNotifierProvider<AuthController, AuthState>(AuthController.new);

class AuthController extends AsyncNotifier<AuthState> {
  @override
  Future<AuthState> build() async {
    final tokens = await ref.read(authTokensStorageProvider).readTokens();

    final next = (tokens == null)
        ? const AuthState.unauthenticated()
        : AuthState.authenticated(tokens);

    _invalidateCaches();
    return next;
  }

  Future<void> login(String email, String password) async {
    state = const AsyncLoading();

    state = await AsyncValue.guard(() async {
      final tokens = await ref.read(authApiProvider).login(
            email: email,
            password: password,
          );

      await ref.read(authTokensStorageProvider).writeTokens(tokens);
      _invalidateCaches();
      return AuthState.authenticated(tokens);
    });
  }

  Future<void> logout() async {
    state = const AsyncLoading();

    state = await AsyncValue.guard(() async {
      await ref.read(authTokensStorageProvider).clear();
      _invalidateCaches();
      return const AuthState.unauthenticated();
    });
  }

  void _invalidateCaches() {
    ref.invalidate(dongleListProvider);
  }
}
