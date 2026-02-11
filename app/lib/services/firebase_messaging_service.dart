import 'dart:async';
import 'dart:ui' show DartPluginRegistrant;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'package:app/config/env_config.dart';
import 'package:app/features/calls/state/call_notifier.dart';
import 'package:app/core/storage/fcm_storage.dart';
import 'package:app/services/app_lifecycle_tracker.dart';
import 'package:app/services/firebase_options_loader.dart';
import 'package:app/services/incoming_notification_service.dart';

class FirebaseMessagingService {
  FirebaseMessagingService._();

  static Future<void> initialize({
    Future<void> Function(String token)? onTokenChanged,
  }) async {
    final firebaseOptions = await FirebaseOptionsLoader.load(
      environment: EnvConfig.env,
    );
    await Firebase.initializeApp(options: firebaseOptions);

    final messaging = FirebaseMessaging.instance;
    await messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    FirebaseMessaging.onMessage.listen(_handleIncomingHint);
    FirebaseMessaging.onMessageOpenedApp.listen(_handleIncomingHint);
    final initialMessage = await messaging.getInitialMessage();
    if (initialMessage != null) {
      await _handleIncomingHint(initialMessage);
    }

    messaging.onTokenRefresh.listen((token) async {
      debugPrint('[FCM] token refreshed');
      await FcmStorage.saveToken(token);
      unawaited(onTokenChanged?.call(token));
    });

    final token = await messaging.getToken();
    if (token != null) {
      debugPrint('[FCM] token: $token');
      await FcmStorage.saveToken(token);
      unawaited(onTokenChanged?.call(token));
    } else {
      debugPrint('[FCM] token unavailable');
    }
  }

  static Future<void> requestPermission() async {
    final messaging = FirebaseMessaging.instance;
    final settings = await messaging.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );
    debugPrint('[FCM] permission status: ${settings.authorizationStatus}');
  }
}

Future<void> _handleIncomingHint(RemoteMessage message) async {
  final type = message.data['type']?.toString();
  final callId = message.data['call_id']?.toString();
  if (type == 'call_cancelled' && callId != null && callId.isNotEmpty) {
    unawaited(requestIncomingCallCancelProcessing(callId));
  }
  final stored = await _storeIncomingHint(message);
  if (!stored) return;

  await _maybeShowIncomingNotification(message.data);
  debugPrint('[FCM] pending incoming hint queued, triggering handler');
  unawaited(requestIncomingCallHintProcessing());
}

Future<bool> _storeIncomingHint(RemoteMessage message) async {
  final rawType = message.data['type']?.toString();
  final currentTime = DateTime.now();
  debugPrint('[FCM] message received payload=$rawType data=${message.data}');

  if (rawType == 'incoming_call' || rawType == 'call_cancelled') {
    await FcmStorage.savePendingIncomingHint(message.data, currentTime);
    if (rawType == 'incoming_call') {
      debugPrint(
        '[FCM] pending incoming hint stored call_uuid=${message.data['call_uuid'] ?? '<none>'} timestamp=$currentTime; app should handle it on next resume/foreground',
      );
    }
    return true;
  }

  return false;
}

Future<void> _maybeShowIncomingNotification(Map<String, dynamic> data) async {
  if (AppLifecycleTracker.isAppInForeground) return;
  final callId = data['call_id']?.toString();
  final from = data['from']?.toString();
  if (callId == null || callId.isEmpty || from == null || from.isEmpty) {
    return;
  }
  final displayName = data['display_name']?.toString();
  await IncomingNotificationService.showIncoming(
    callId: callId,
    from: from,
    displayName: displayName,
    callUuid: data['call_uuid']?.toString(),
  );
}

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  DartPluginRegistrant.ensureInitialized();
  final firebaseOptions = await FirebaseOptionsLoader.load(
    environment: EnvConfig.env,
  );
  await Firebase.initializeApp(options: firebaseOptions);
  debugPrint('[FCM][bg] background message data=${message.data}');
  await _storeIncomingHint(message);
}
