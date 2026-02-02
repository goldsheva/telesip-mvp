import 'package:app/state/auth/auth_state.dart';
import 'package:app/state/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final authControllerProvider =
    NotifierProvider<AuthController, AuthState>(AuthController.new);

class AuthController extends Notifier<AuthState> {
  @override
  AuthState build() {
    _bootstrap(); // async init
    return const AuthState.unknown();
  }

  Future<void> _bootstrap() async {
    final tokens = await ref.read(authTokensStorageProvider).readTokens();
    state = (tokens == null)
        ? const AuthState.unauthenticated()
        : AuthState.authenticated(tokens);
  }

  Future<void> login(String email, String password) async {
    try {
      final tokens = await ref.read(authApiProvider).login(
            email: email,
            password: password,
          );

      await ref.read(authTokensStorageProvider).writeTokens(tokens);
      state = AuthState.authenticated(tokens);
    } catch (e) {
      state = AuthState.unauthenticated(error: e.toString());
    }
  }

  Future<void> logout() async {
    await ref.read(authTokensStorageProvider).clear();
    state = const AuthState.unauthenticated();
  }
}
