import 'dart:convert';

import 'package:app/features/auth/models/auth_tokens.dart';
import 'package:http/http.dart' as http;

typedef TokensReader = Future<AuthTokens?> Function();
typedef TokensWriter = Future<void> Function(AuthTokens tokens);
typedef TokensClear = Future<void> Function();
typedef RefreshFn = Future<AuthTokens> Function(String refreshToken);
typedef AuthLostCallback = void Function();

class ApiClient {
  ApiClient({
    required TokensReader readTokens,
    required TokensWriter writeTokens,
    required TokensClear clearTokens,
    required RefreshFn refresh,
    AuthLostCallback? onAuthLost,
    http.Client? client,
  })  : _readTokens = readTokens,
        _writeTokens = writeTokens,
        _clearTokens = clearTokens,
        _refresh = refresh,
        _onAuthLost = onAuthLost,
        _client = client ?? http.Client();

  final TokensReader _readTokens;
  final TokensWriter _writeTokens;
  final TokensClear _clearTokens;
  final RefreshFn _refresh;
  final AuthLostCallback? _onAuthLost;
  final http.Client _client;

  Future<AuthTokens>? _refreshInFlight;

  Future<http.Response> get(String apiUri) => _request('GET', apiUri);

  Future<http.Response> post(String apiUri, Map<String, dynamic> body) {
    return _request('POST', apiUri, body: body);
  }

  Future<http.Response> _request(
    String method,
    String apiUri, {
    Map<String, dynamic>? body,
    bool isRetriedAfterRefresh = false,
  }) async {
    final uri = Uri.parse(apiUri);
    final tokens = await _readTokens();

    final headers = <String, String>{
      'Content-Type': 'application/json',
      if (tokens != null) 'Authorization': 'Bearer ${tokens.accessToken}',
    };

    final response = await _send(method, uri, headers: headers, body: body);

    if (response.statusCode == 401 && !isRetriedAfterRefresh) {
      final refreshed = await _tryRefresh(tokens);

      if (refreshed == null) {
        await _clearTokens();
        _onAuthLost?.call();
        return response;
      }

      return _request(method, apiUri, body: body, isRetriedAfterRefresh: true);
    }

    return response;
  }

  Future<http.Response> _send(
    String method,
    Uri uri, {
    required Map<String, String> headers,
    Map<String, dynamic>? body,
  }) {
    switch (method) {
      case 'GET':
        return _client.get(uri, headers: headers);
      case 'POST':
        return _client.post(uri, headers: headers, body: jsonEncode(body ?? {}));
      default:
        throw UnsupportedError('Unsupported method: $method');
    }
  }

  Future<AuthTokens?> _tryRefresh(AuthTokens? currentTokens) async {
    final refreshToken = currentTokens?.refreshToken;
    if (refreshToken == null || refreshToken.isEmpty) return null;

    _refreshInFlight ??= _refresh(refreshToken);

    try {
      final newTokens = await _refreshInFlight!;
      await _writeTokens(newTokens);
      return newTokens;
    } catch (_) {
      return null;
    } finally {
      _refreshInFlight = null;
    }
  }

  void dispose() => _client.close();
}
