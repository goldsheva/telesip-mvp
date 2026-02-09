import 'dart:async';
import 'dart:ui' show DartPluginRegistrant;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'package:app/features/calls/state/call_notifier.dart';
import 'package:app/core/storage/fcm_storage.dart';

class FirebaseMessagingService {
  FirebaseMessagingService._();

  static Future<void> initialize() async {
    await Firebase.initializeApp();

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
    });

    final token = await messaging.getToken();
    if (token != null) {
      debugPrint('[FCM] token: $token');
      await FcmStorage.saveToken(token);
    } else {
      debugPrint('[FCM] token unavailable');
    }
  }
}

Future<void> _handleIncomingHint(RemoteMessage message) async {
  final stored = await _storeIncomingHint(message);
  if (!stored) return;
  debugPrint('[FCM] pending incoming hint queued, triggering handler');
  unawaited(requestIncomingCallHintProcessing());
}

Future<bool> _storeIncomingHint(RemoteMessage message) async {
  final rawType = message.data['type']?.toString();
  debugPrint('[FCM] message received payload=$rawType data=${message.data}');
  if (rawType != 'incoming_call') {
    return false;
  }

  final timestamp = DateTime.now();
  await FcmStorage.savePendingIncomingHint(message.data, timestamp);
  debugPrint(
    '[FCM] pending incoming hint stored call_uuid=${message.data['call_uuid'] ?? '<none>'} timestamp=$timestamp; app should handle it on next resume/foreground',
  );
  return true;
}

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  DartPluginRegistrant.ensureInitialized();
  await Firebase.initializeApp();
  debugPrint('[FCM][bg] background message data=${message.data}');
  await _storeIncomingHint(message);
}
