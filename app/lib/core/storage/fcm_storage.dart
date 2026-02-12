import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:app/core/storage/secure_storage.dart';

class FcmStorage {
  static const _tokenKey = 'fcm_token';
  static const _pendingIncomingKey = 'pending_incoming_hint';

  static final FlutterSecureStorage _storage = SecureStorage.instance;

  static Future<void> saveToken(String token) {
    return _storage.write(key: _tokenKey, value: token);
  }

  static Future<String?> readToken() {
    return _storage.read(key: _tokenKey);
  }

  static Future<void> savePendingIncomingHint(
    Map<String, dynamic> payload,
    DateTime timestamp,
  ) {
    final record = jsonEncode({
      'timestamp': timestamp.toIso8601String(),
      'payload': payload,
    });
    return _storage.write(key: _pendingIncomingKey, value: record);
  }

  static Future<Map<String, dynamic>?> readPendingIncomingHint() async {
    final raw = await _storage.read(key: _pendingIncomingKey);
    if (raw == null || raw.isEmpty) {
      return null;
    }

    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      return null;
    }

    return decoded;
  }

  static Future<void> clearPendingIncomingHint() {
    return _storage.delete(key: _pendingIncomingKey);
  }
}
