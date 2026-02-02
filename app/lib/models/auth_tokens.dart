class AuthTokens {
    final String accessToken;
    final String refreshToken;

    const AuthTokens({required this.accessToken, required this.refreshToken});

    factory AuthTokens.fromJson(Map<String, dynamic> json) {
        return AuthTokens(
            accessToken: json['access_token'] as String,
            refreshToken: json['refresh_token'] as String,
        );
    }
}
