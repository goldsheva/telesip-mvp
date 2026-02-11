import 'package:shared_preferences/shared_preferences.dart';

class BatteryOptimizationPromptStorage {
  static const _key = 'battery_opt_prompt_shown';

  static Future<bool> readPromptShown() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key) ?? false;
  }

  static Future<void> markPromptShown() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, true);
  }
}
