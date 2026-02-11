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
    String? callUuid,
    bool isRinging = true,
  }) async {
    try {
      final args = <String, dynamic>{'callId': callId, 'from': from};
      if (displayName != null) {
        args['displayName'] = displayName;
      }
      args['callUuid'] = callUuid ?? callId;
      args['isRinging'] = isRinging;
      if (kDebugMode) {
        debugPrint(
          '[CALLS_NOTIF] showIncoming callId=$callId callUuid=${args['callUuid']} isRinging=$isRinging',
        );
      }
      await _channel.invokeMethod('showIncoming', args);
    } catch (error) {
      debugPrint('[CALLS_NOTIF] showIncoming failed: $error');
    }
  }

  static Future<void> updateIncomingState({
    required String callId,
    required String from,
    String? displayName,
    String? callUuid,
    required bool isRinging,
  }) async {
    try {
      final args = <String, dynamic>{
        'callId': callId,
        'from': from,
        'isRinging': isRinging,
      };
      if (displayName != null) {
        args['displayName'] = displayName;
      }
      if (callUuid != null) {
        args['callUuid'] = callUuid;
      }
      await _channel.invokeMethod('updateIncomingState', args);
    } catch (error) {
      debugPrint('[CALLS_NOTIF] updateIncomingState failed: $error');
    }
  }

  static Future<void> cancelIncoming({required String callId}) async {
    try {
      await _channel.invokeMethod('cancelIncoming', <String, dynamic>{
        'callId': callId,
      });
      await clearCallAction();
    } catch (error) {
      debugPrint('[CALLS_NOTIF] cancelIncoming failed: $error');
    }
  }

  static Future<Map<String, dynamic>?> readCallAction() async {
    try {
      return await _channel.invokeMapMethod<String, dynamic>('readCallAction');
    } catch (error) {
      debugPrint('[CALLS_NOTIF] readCallAction failed: $error');
      return null;
    }
  }

  static Future<void> clearCallAction() async {
    try {
      await _channel.invokeMethod('clearCallAction');
    } catch (error) {
      debugPrint('[CALLS_NOTIF] clearCallAction failed: $error');
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
