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
}
