import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'dart:ui' show DartPluginRegistrant;

import 'package:flutter/foundation.dart';

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
  await _storeIncomingHint(message);
}

Future<void> _storeIncomingHint(RemoteMessage message) async {
  final rawType = message.data['type']?.toString();
  debugPrint('[FCM] message received payload=$rawType data=${message.data}');
  if (rawType != 'incoming_call') {
    return;
  }

  final timestamp = DateTime.now();
  await FcmStorage.savePendingIncomingHint(message.data, timestamp);
  debugPrint(
    '[FCM] pending incoming hint stored call_uuid=${message.data['call_uuid'] ?? '<none>'} timestamp=$timestamp',
  );
}

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  DartPluginRegistrant.ensureInitialized();
  await Firebase.initializeApp();
  debugPrint('[FCM][bg] background message data=${message.data}');
  await _storeIncomingHint(message);
}
