import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SipAuthSnapshot {
  const SipAuthSnapshot({
    required this.uri,
    required this.password,
    required this.wsUrl,
    this.displayName,
    required this.timestamp,
  });

  final String uri;
  final String password;
  final String wsUrl;
  final String? displayName;
  final DateTime timestamp;

  Map<String, String> toJson() => <String, String>{
    'uri': uri,
    'password': password,
    'ws_url': wsUrl,
    'display_name': displayName ?? '',
    'timestamp': timestamp.toIso8601String(),
  };

  factory SipAuthSnapshot.fromJson(Map<String, dynamic> json) {
    final tsValue = json['timestamp'] as String?;
    final timestamp = DateTime.tryParse(tsValue ?? '') ?? DateTime.now();
    return SipAuthSnapshot(
      uri: json['uri'] as String? ?? '',
      password: json['password'] as String? ?? '',
      wsUrl: json['ws_url'] as String? ?? '',
      displayName: (() {
        final raw = json['display_name'] as String?;
        if (raw == null || raw.isEmpty) {
          return null;
        }
        return raw;
      })(),
      timestamp: timestamp,
    );
  }
}

class SipAuthStorage {
  SipAuthStorage(this._storage);

  final FlutterSecureStorage _storage;

  static const _key = 'sip_auth_snapshot';

  Future<void> writeSnapshot(SipAuthSnapshot snapshot) {
    return _storage.write(key: _key, value: jsonEncode(snapshot.toJson()));
  }

  Future<SipAuthSnapshot?> readSnapshot() async {
    final raw = await _storage.read(key: _key);
    if (raw == null || raw.isEmpty) return null;

    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) return null;

    return SipAuthSnapshot.fromJson(decoded);
  }

  Future<void> clearSnapshot() {
    return _storage.delete(key: _key);
  }
}
