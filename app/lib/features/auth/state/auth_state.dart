import 'package:app/features/auth/models/auth_tokens.dart';

enum AuthStatus { unknown, unauthenticated, authenticated }

class AuthState {
  final AuthStatus status;
  final AuthTokens? tokens;
  final String? error;

  const AuthState._(this.status, {this.tokens, this.error});

  const AuthState.unknown() : this._(AuthStatus.unknown);

  const AuthState.unauthenticated({String? error})
    : this._(AuthStatus.unauthenticated, error: error);

  const AuthState.authenticated(AuthTokens tokens)
    : this._(AuthStatus.authenticated, tokens: tokens);
}
