import 'dart:convert';

import 'package:app/config/env_config.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/services.dart';

/// Helper that loads platform-dependent Firebase credentials from a JSON asset.
class FirebaseOptionsLoader {
  static const _assetPath = 'assets/firebase/firebase_options.json';

  static Future<FirebaseOptions> load({
    Environment environment = Environment.prod,
  }) async {
    final raw = await rootBundle.loadString(_assetPath);
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw StateError('$_assetPath must contain a map of environments.');
    }

    final envData = decoded[environment.name];
    if (envData is! Map<String, dynamic>) {
      throw StateError(
        'Firebase configuration for "${environment.name}" not found in $_assetPath.',
      );
    }

    return FirebaseOptions(
      apiKey: _requireValue(envData, 'apiKey'),
      appId: _requireValue(envData, 'appId'),
      messagingSenderId: _requireValue(envData, 'messagingSenderId'),
      projectId: _requireValue(envData, 'projectId'),
      authDomain: envData['authDomain'] as String?,
      databaseURL: envData['databaseURL'] as String?,
      storageBucket: envData['storageBucket'] as String?,
      measurementId: envData['measurementId'] as String?,
    );
  }

  static String _requireValue(Map<String, dynamic> data, String key) {
    final value = data[key];
    if (value is! String || value.isEmpty) {
      throw StateError('Firebase configuration is missing a non-empty "$key".');
    }
    return value;
  }
}
