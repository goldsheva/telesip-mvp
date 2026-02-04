import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:app/core/network/api_exception.dart';
import 'package:app/core/providers.dart';
import 'package:app/features/dongles/state/dongle_list_notifier.dart';
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
    state = const AsyncLoading();

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

  void _invalidateCaches() {
    ref.invalidate(dongleListProvider);
  }

  String _messageFrom(Object error) {
    if (error is ApiException) {
      return error.message;
    }

    return error.toString();
  }
}
