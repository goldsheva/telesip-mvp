import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class IncomingNotificationService {
  IncomingNotificationService._();

  static const MethodChannel _channel = MethodChannel(
    'app.calls/notifications',
  );

  static Future<void> showIncoming({
    required String callId,
    required String from,
    String? displayName,
  }) async {
    try {
      final args = <String, dynamic>{'callId': callId, 'from': from};
      if (displayName != null) {
        args['displayName'] = displayName;
      }
      await _channel.invokeMethod('showIncoming', args);
    } catch (error) {
      debugPrint('[CALLS_NOTIF] showIncoming failed: $error');
    }
  }

  static Future<void> cancelIncoming({required String callId}) async {
    try {
      await _channel.invokeMethod('cancelIncoming', <String, dynamic>{
        'callId': callId,
      });
    } catch (error) {
      debugPrint('[CALLS_NOTIF] cancelIncoming failed: $error');
    }
  }

  static Future<void> cancelAll() async {
    try {
      await _channel.invokeMethod('cancelAll');
    } catch (error) {
      debugPrint('[CALLS_NOTIF] cancelAll failed: $error');
    }
  }

  static Future<void> setEngineAlive(bool alive) async {
    try {
      await _channel.invokeMethod('setEngineAlive', <String, dynamic>{
        'alive': alive,
      });
    } catch (error) {
      debugPrint('[CALLS_NOTIF] setEngineAlive failed: $error');
    }
  }
}
