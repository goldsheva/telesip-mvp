import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class SystemSettings {
  static const _channel = MethodChannel('app.system_settings');

  static Future<void> openIgnoreBatteryOptimizations() async {
    try {
      await _channel.invokeMethod('openIgnoreBatteryOptimizations');
    } catch (error) {
      debugPrint('Battery optimization settings unavailable: $error');
    }
  }

  static Future<bool> isIgnoringBatteryOptimizations() async {
    try {
      final result = await _channel.invokeMethod<bool>(
        'isIgnoringBatteryOptimizations',
      );
      return result ?? false;
    } catch (error) {
      debugPrint('Battery optimization query failed: $error');
      return false;
    }
  }
}
