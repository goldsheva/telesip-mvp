import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorage {
  SecureStorage._();

  static final FlutterSecureStorage instance = const FlutterSecureStorage(
    aOptions: _androidOptions,
  );

  static const AndroidOptions _androidOptions = AndroidOptions(
    // ignore: deprecated_member_use
    encryptedSharedPreferences: true,
    resetOnError: true,
    sharedPreferencesName: 'sip_mvp_secure_storage',
    preferencesKeyPrefix: 'sip_mvp.v1.',
  );

  static bool _warmUpDone = false;

  static Future<void> warmUp() async {
    if (_warmUpDone) return;
    try {
      await instance.read(key: '__warmup__');
    } catch (error) {
      if (kDebugMode) {
        log('[SECURE_STORAGE] warmup failed: $error');
      }
    } finally {
      _warmUpDone = true;
    }
  }
}
