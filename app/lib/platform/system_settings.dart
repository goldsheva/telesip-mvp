import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class SystemSettings {
  static const _channel = MethodChannel('app.system_settings');

  static Future<bool> openIgnoreBatteryOptimizations() async {
    try {
      final result = await _channel.invokeMethod<bool>(
        'openIgnoreBatteryOptimizations',
      );
      debugPrint(
        '[SYSTEM] ignore battery optimizations intent triggered result=$result',
      );
      return result ?? false;
    } catch (error) {
      debugPrint('Battery optimization settings unavailable: $error');
      return Future.error(error);
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

  static Future<bool> isRunningOnEmulator() async {
    try {
      final result = await _channel.invokeMethod<bool>('isRunningOnEmulator');
      return result ?? false;
    } catch (error) {
      debugPrint('[SYSTEM] emulator check failed: $error');
      return false;
    }
  }
}
