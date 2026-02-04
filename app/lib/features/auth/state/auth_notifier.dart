import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:app/core/providers.dart';
import 'package:app/features/dongles/state/dongle_list_notifier.dart';
import 'auth_state.dart';

final authNotifierProvider =
    AsyncNotifierProvider<AuthNotifier, AuthState>(AuthNotifier.new);

class AuthNotifier extends AsyncNotifier<AuthState> {
  @override
  Future<AuthState> build() async {
    try {
      final tokens = await ref.read(authTokensStorageProvider).readTokens();

      final next = (tokens == null)
          ? const AuthState.unauthenticated()
          : AuthState.authenticated(tokens);

      _invalidateCaches();
      return next;
    } catch (e) {
      _invalidateCaches();
      return AuthState.unauthenticated(error: e.toString());
    }
  }

  Future<void> login(String email, String password) async {
    state = const AsyncLoading();

    try {
      final tokens = await ref.read(authApiProvider).login(
            email: email,
            password: password,
          );

      await ref.read(authTokensStorageProvider).writeTokens(tokens);
      _invalidateCaches();
      state = AsyncData(AuthState.authenticated(tokens));
    } catch (e) {
      _invalidateCaches();
      state = AsyncData(AuthState.unauthenticated(error: e.toString()));
    }
  }

  Future<void> logout() async {
    state = const AsyncLoading();

    try {
      await ref.read(authTokensStorageProvider).clear();
      _invalidateCaches();
      state = const AsyncData(AuthState.unauthenticated());
    } catch (e) {
      _invalidateCaches();
      state = AsyncData(AuthState.unauthenticated(error: e.toString()));
    }
  }

  void _invalidateCaches() {
    ref.invalidate(dongleListProvider);
  }
}
