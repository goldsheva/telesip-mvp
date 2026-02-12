import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:app/core/storage/secure_storage.dart';

class FcmStorage {
  static const _tokenKey = 'fcm_token';
  static const _pendingIncomingKey = 'sip_mvp.v1.pending_incoming_hint';
  static const MethodChannel _nativeStorageChannel = MethodChannel(
    'app.storage/native',
  );
  static const AndroidOptions _androidPendingHintOptions = AndroidOptions(
    // ignore: deprecated_member_use, deprecated_member_use_from_same_package
    encryptedSharedPreferences: true,
    resetOnError: true,
    sharedPreferencesName: 'sip_mvp_secure_storage',
    preferencesKeyPrefix: '',
  );

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
    final futures = <Future<void>>[];
    if (_isAndroidPlatform) {
      futures.add(_persistPendingIncomingHintNative(record));
    }
    // TODO: remove FlutterSecureStorage write once the native writer is fully rolled out.
    futures.add(_writePendingIncomingHintLegacy(record));
    return Future.wait(futures).then((_) {});
  }

  static Future<Map<String, dynamic>?> readPendingIncomingHint() async {
    if (_isAndroidPlatform) {
      final nativeRaw = await _readPendingIncomingHintNative();
      final nativeDecoded = _decodePendingIncomingHint(
        nativeRaw,
        source: 'native',
      );
      if (nativeDecoded != null) {
        return nativeDecoded;
      }
    }

    final fallbackRaw = await _readPendingIncomingHintLegacy();
    return _decodePendingIncomingHint(fallbackRaw, source: 'legacy');
  }

  static Future<void> clearPendingIncomingHint() {
    final futures = <Future<void>>[_clearPendingIncomingHintLegacy()];
    if (_isAndroidPlatform) {
      futures.add(_clearPendingIncomingHintNative());
    }
    return Future.wait(futures).then((_) {});
  }

  static bool get _isAndroidPlatform =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<void> _persistPendingIncomingHintNative(String record) async {
    try {
      await _nativeStorageChannel.invokeMethod<void>(
        'persistPendingIncomingHint',
        record,
      );
    } catch (error, stackTrace) {
      debugPrint(
        '[FcmStorage] native pending hint persist failed: $error\n$stackTrace',
      );
    }
  }

  static Future<String?> _readPendingIncomingHintNative() async {
    try {
      final raw = await _nativeStorageChannel.invokeMethod<String>(
        'readPendingIncomingHint',
      );
      return raw;
    } catch (error, stackTrace) {
      debugPrint(
        '[FcmStorage] native pending hint read failed: $error\n$stackTrace',
      );
      return null;
    }
  }

  static Future<void> _clearPendingIncomingHintNative() async {
    try {
      await _nativeStorageChannel.invokeMethod<void>(
        'clearPendingIncomingHint',
      );
    } catch (error, stackTrace) {
      debugPrint(
        '[FcmStorage] native pending hint clear failed: $error\n$stackTrace',
      );
    }
  }

  static Future<String?> _readPendingIncomingHintLegacy() {
    if (_isAndroidPlatform) {
      return _storage.read(
        key: _pendingIncomingKey,
        aOptions: _androidPendingHintOptions,
      );
    }
    return _storage.read(key: _pendingIncomingKey);
  }

  static Future<void> _writePendingIncomingHintLegacy(String record) {
    if (_isAndroidPlatform) {
      return _storage.write(
        key: _pendingIncomingKey,
        value: record,
        aOptions: _androidPendingHintOptions,
      );
    }
    return _storage.write(key: _pendingIncomingKey, value: record);
  }

  static Future<void> _clearPendingIncomingHintLegacy() {
    if (_isAndroidPlatform) {
      return _storage.delete(
        key: _pendingIncomingKey,
        aOptions: _androidPendingHintOptions,
      );
    }
    return _storage.delete(key: _pendingIncomingKey);
  }

  static Map<String, dynamic>? _decodePendingIncomingHint(
    String? raw, {
    required String source,
  }) {
    if (raw == null || raw.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    } catch (error, stackTrace) {
      debugPrint(
        '[FcmStorage] $source pending hint decode failed: $error\n$stackTrace',
      );
    }
    return null;
  }
}
