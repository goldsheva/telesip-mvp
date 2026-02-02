import 'dart:convert';
import 'package:app/models/auth_tokens.dart';
import 'package:http/http.dart' as http;

typedef TokensReader = Future<AuthTokens?> Function();
typedef TokensWriter = Future<void> Function(AuthTokens tokens);
typedef TokensClear = Future<void> Function();
typedef RefreshFn = Future<AuthTokens> Function(String refreshToken);

class ApiClient {
  ApiClient({
    required TokensReader readTokens,
    required TokensWriter writeTokens,
    required TokensClear clearTokens,
    required RefreshFn refresh,
  })  : _readTokens = readTokens,
        _writeTokens = writeTokens,
        _clearTokens = clearTokens,
        _refresh = refresh;

  final TokensReader _readTokens;
  final TokensWriter _writeTokens;
  final TokensClear _clearTokens;
  final RefreshFn _refresh;

  Future<AuthTokens>? _refreshInFlight;

  Future<http.Response> get(String apiUri) async {
    return _request('GET', apiUri);
  }

  Future<http.Response> post(String apiUri, Map<String, dynamic> body) async {
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

    http.Response response;

    switch(method) {
      case 'GET':
        response = await http.get(uri, headers: headers);
      case 'POST':
        response = await http.post(uri, headers: headers, body: jsonEncode(body ?? {}));
      default:
        throw UnsupportedError('Unsupported method: $method');
    }

    if (response.statusCode == 401 && !isRetriedAfterRefresh) {
      final refreshed = await _tryRefresh(tokens);
      if (refreshed == null) {
        await _clearTokens();
        return response;
      }
  
      return _request(method, apiUri, body: body, isRetriedAfterRefresh: true);
    }

    return response;
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
}
