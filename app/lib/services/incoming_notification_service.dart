import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class IncomingNotificationService {
  IncomingNotificationService._();

  static const MethodChannel _channel = MethodChannel(
    'app.calls/notifications',
  );
  static const MethodChannel _incomingChannel = MethodChannel(
    'app.calls/incoming',
  );

  static Future<void> showIncoming({
    required String callId,
    required String from,
    String? displayName,
    String? callUuid,
    bool isRinging = true,
  }) async {
    _logAndroidNotificationState('showIncoming');
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

  static Future<void> refreshPendingIncomingNotification() async {
    try {
      final refreshed = await _incomingChannel.invokeMethod<bool>(
        'refreshIncomingNotification',
      );
      debugPrint(
        '[CALLS_NOTIF] refreshPendingIncomingNotification result=${refreshed ?? false}',
      );
    } catch (error) {
      debugPrint(
        '[CALLS_NOTIF] refreshPendingIncomingNotification failed: $error',
      );
    }
  }

  static Future<void> updateIncomingState({
    required String callId,
    required String from,
    String? displayName,
    String? callUuid,
    required bool isRinging,
  }) async {
    _logAndroidNotificationState('updateIncomingState');
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
      if (kDebugMode) {
        debugPrint(
          '[CALLS_NOTIF] updateIncomingState callId=$callId callUuid=${callUuid ?? '<none>'} '
          'from=$from display=${displayName ?? '<none>'} isRinging=$isRinging',
        );
      }
    } catch (error) {
      debugPrint('[CALLS_NOTIF] updateIncomingState failed: $error');
    }
  }

  static Future<void> cancelIncoming({
    required String callId,
    String? callUuid,
  }) async {
    _logAndroidNotificationState('cancelIncoming');
    try {
      final args = <String, dynamic>{'callId': callId};
      if (callUuid != null) {
        args['callUuid'] = callUuid;
      }
      if (kDebugMode) {
        debugPrint(
          '[CALLS_NOTIF] cancelIncoming callId=$callId callUuid=${callUuid ?? '<none>'}',
        );
      }
      await _channel.invokeMethod('cancelIncoming', args);
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

  static Future<Map<String, dynamic>?> getNotificationDebugState() async {
    try {
      return await _channel.invokeMapMethod<String, dynamic>(
        'getNotificationDebugState',
      );
    } catch (_) {
      return null;
    }
  }

  static Future<List<Map<String, dynamic>>?> drainPendingCallActions() async {
    try {
      return await _channel.invokeListMethod<Map<String, dynamic>>(
        'drainPendingCallActions',
      );
    } catch (error) {
      debugPrint('[CALLS_NOTIF] drainPendingCallActions failed: $error');
      return null;
    }
  }

  static const Duration _androidStateLogMinGap = Duration(seconds: 1);
  static DateTime? _lastAndroidStateLogAt;

  static Future<void> _logAndroidNotificationState(String method) async {
    if (!kDebugMode) return;
    final now = DateTime.now();
    if (_lastAndroidStateLogAt != null &&
        now.difference(_lastAndroidStateLogAt!) < _androidStateLogMinGap) {
      return;
    }
    _lastAndroidStateLogAt = now;
    final state = await getNotificationDebugState();
    if (state == null) return;
    debugPrint(
      '[CALLS_NOTIF] androidState $method enabled=${state['notificationsEnabled']} '
      'postPerm=${state['hasPostNotificationsPermission']} channelExists=${state['channelExists']} '
      'channelEnabled=${state['channelEnabled']} importance=${state['channelImportance']} '
      'keyguardLocked=${state['keyguardLocked']}',
    );
  }

  static Future<void> logAndroidStateNow(String tag) async {
    if (!kDebugMode) return;
    final state = await getNotificationDebugState();
    if (state == null) return;
    debugPrint(
      '[CALLS_NOTIF] androidState $tag enabled=${state['notificationsEnabled']} '
      'postPerm=${state['hasPostNotificationsPermission']} channelExists=${state['channelExists']} '
      'channelEnabled=${state['channelEnabled']} importance=${state['channelImportance']} '
      'keyguardLocked=${state['keyguardLocked']}',
    );
  }
}
