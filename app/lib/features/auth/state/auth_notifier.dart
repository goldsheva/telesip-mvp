import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:app/core/network/api_exception.dart';
import 'package:app/core/providers.dart';
import 'package:app/features/dongles/state/dongles_provider.dart';
import 'package:app/features/sip_users/state/sip_users_provider.dart';
import 'auth_state.dart';

final authNotifierProvider = AsyncNotifierProvider<AuthNotifier, AuthState>(
  AuthNotifier.new,
);

class AuthNotifier extends AsyncNotifier<AuthState> {
  @override
  Future<AuthState> build() async {
    try {
      final tokens = await ref.read(authTokensStorageProvider).readTokens();

      final next = (tokens == null)
          ? const AuthState.unauthenticated()
          : AuthState.authenticated(tokens);

      return next;
    } catch (e) {
      return AuthState.unauthenticated(error: _messageFrom(e));
    }
  }

  Future<void> login(String email, String password) async {
    try {
      final tokens = await ref
          .read(authApiProvider)
          .login(email: email, password: password);

      await ref.read(authTokensStorageProvider).writeTokens(tokens);
      state = AsyncData(AuthState.authenticated(tokens));
      _invalidateCaches();
    } catch (e) {
      state = AsyncData(AuthState.unauthenticated(error: _messageFrom(e)));
    }
  }

  Future<void> logout() async {
    state = const AsyncLoading();

    try {
      await ref.read(authTokensStorageProvider).clear();
      state = const AsyncData(AuthState.unauthenticated());
      _invalidateCaches();
    } catch (e) {
      state = AsyncData(AuthState.unauthenticated(error: _messageFrom(e)));
    }
  }

  Future<void> loginWithBiometrics() async {
    try {
      final storage = ref.read(authTokensStorageProvider);
      final tokens = await storage.readTokens();
      if (tokens == null) {
        throw ApiException.network(
          'Please log in with credentials before enabling biometrics',
        );
      }

      final refreshed = await ref
          .read(authApiProvider)
          .refreshToken(refreshToken: tokens.refreshToken);

      await storage.writeTokens(refreshed);
      state = AsyncData(AuthState.authenticated(refreshed));
      _invalidateCaches();
    } catch (e) {
      state = AsyncData(AuthState.unauthenticated(error: _messageFrom(e)));
    }
  }

  void _invalidateCaches() {
    ref.invalidate(sipUsersProvider);
    ref.invalidate(donglesProvider);
  }

  String _messageFrom(Object error) {
    if (error is ApiException) {
      return error.message;
    }

    return error.toString();
  }
}
