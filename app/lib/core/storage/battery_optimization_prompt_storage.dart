import 'package:shared_preferences/shared_preferences.dart';

class BatteryOptimizationPromptStorage {
  static const _key = 'battery_opt_prompt_shown';
  static const _snoozeKey = 'battery_opt_prompt_snooze_until';

  static Future<bool> readPromptShown() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key) ?? false;
  }

  static Future<void> markPromptShown() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, true);
  }

  static Future<int?> readSnoozeUntilMillis() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_snoozeKey);
  }

  static Future<void> setSnooze(Duration duration) async {
    final prefs = await SharedPreferences.getInstance();
    final until = DateTime.now().add(duration).millisecondsSinceEpoch;
    await prefs.setInt(_snoozeKey, until);
  }

  static Future<void> clearSnooze() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_snoozeKey);
  }
}
