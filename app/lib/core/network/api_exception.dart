import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:app/core/network/api_error.dart';

class ApiException implements Exception {
  ApiException(this.statusCode, {required this.message, this.payload});

  ApiException.network(this.message) : statusCode = 0, payload = null;

  final int statusCode;
  final String message;
  final ApiError? payload;

  @override
  String toString() => message;

  factory ApiException.fromResponse(http.Response response) {
    final payload = _tryParseError(response.body);
    final message = payload?.fallbackMessage ?? 'HTTP ${response.statusCode}';
    return ApiException(
      response.statusCode,
      message: message,
      payload: payload,
    );
  }
}

ApiError? _tryParseError(String body) {
  if (body.isEmpty) return null;
  try {
    final jsonBody = jsonDecode(body);
    if (jsonBody is Map<String, dynamic>) {
      return ApiError.fromJson(jsonBody);
    }
  } catch (_) {
    // ignore
  }

  return null;
}
