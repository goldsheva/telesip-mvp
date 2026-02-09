import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class ForegroundService {
  static const _channel = MethodChannel('app.foreground_service');

  static Future<void> startForegroundService() async {
    try {
      await _channel.invokeMethod('startForegroundService');
    } catch (error) {
      debugPrint('Foreground service start failed: $error');
    }
  }

  static Future<void> stopForegroundService() async {
    try {
      await _channel.invokeMethod('stopForegroundService');
    } catch (error) {
      debugPrint('Foreground service stop failed: $error');
    }
  }
}
