import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class BatteryOptimizationPromptStorage {
  static const _key = 'battery_opt_prompt_shown';
  static final FlutterSecureStorage _storage = const FlutterSecureStorage();

  static Future<bool> readPromptShown() async {
    final value = await _storage.read(key: _key);
    return value == '1';
  }

  static Future<void> markPromptShown() {
    return _storage.write(key: _key, value: '1');
  }
}
