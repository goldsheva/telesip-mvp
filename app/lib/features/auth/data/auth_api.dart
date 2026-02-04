import 'dart:convert';

import 'package:app/core/network/api_endpoints.dart';
import 'package:app/core/network/api_exception.dart';
import 'package:app/config/env_config.dart';
import 'package:app/features/auth/models/auth_tokens.dart';
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
      body: jsonEncode({
        'login': email,
        'password': password,
        'site_domain_id': EnvConfig.siteDomainId,
      }),
    );

    return _parseTokens(response);
  }

  Future<AuthTokens> refreshToken({required String refreshToken}) async {
    final response = await _client.post(
      Uri.parse(ApiEndpoints.authRefresh),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'refresh_token': refreshToken}),
    );

    return _parseTokens(response);
  }

  AuthTokens _parseTokens(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException.fromResponse(response);
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
