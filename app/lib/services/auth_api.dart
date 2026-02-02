import 'dart:convert';
import 'package:app/config/api_endpoints.dart';
import 'package:app/models/auth_tokens.dart';
import 'package:http/http.dart' as http;

class AuthApi {
  AuthApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<AuthTokens> login({
    required String email,
    required String password,
  }) async {
    final response = await _client.post(
      Uri.parse(ApiEndpoints.authLogin),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'password': password}),
    );

    return _parseTokens(response, errorPrefix: 'Login failed');
  }

  Future<AuthTokens> refreshToken({required String refreshToken}) async {
    final response = await _client.post(
      Uri.parse(ApiEndpoints.authRefresh),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'refresh_token': refreshToken}),
    );

    return _parseTokens(response, errorPrefix: 'Refresh failed');
  }

  AuthTokens _parseTokens(http.Response response, {required String errorPrefix}) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('$errorPrefix: ${response.statusCode} ${response.body}');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Unexpected response: ${response.body}');
    }

    final data = decoded['data'];
    if (data is! Map<String, dynamic>) {
      throw Exception('Missing "data" in response: ${response.body}');
    }

    return AuthTokens.fromJson(data);
  }

  void dispose() => _client.close();
}
