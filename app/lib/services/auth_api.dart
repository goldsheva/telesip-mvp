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
    final uri = Uri.parse(ApiEndpoints.authLogin);

    final response = await _client.post(
      uri,
      body: jsonEncode({'email': email, 'password': password}),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Login failed: ${response.statusCode} ${response.body}');
    }

    final decodedBody = jsonDecode(response.body);
    if (decodedBody is! Map<String, dynamic>) {
      throw Exception('Unexpected response: ${response.body}');
    }

    final data = decodedBody['data'];
    if (data is! Map<String, dynamic>) {
      throw Exception('Missing "data" in response: ${response.body}');
    }

    return AuthTokens.fromJson(data);
  }

  Future<AuthTokens> refreshToken({required String refreshToken}) async {
    final uri = Uri.parse(ApiEndpoints.authRefresh);

    final response = await _client.post(
      uri,
      body: jsonEncode({'refresh_token': refreshToken}),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Refresh failed: ${response.statusCode} ${response.body}');
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
