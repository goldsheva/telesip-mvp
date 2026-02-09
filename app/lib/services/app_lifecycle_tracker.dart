import 'package:flutter/widgets.dart';

import 'package:app/services/incoming_notification_service.dart';

/// Tracks whether the Flutter UI is currently in the foreground.
class AppLifecycleTracker {
  AppLifecycleTracker._();

  static bool isAppInForeground = false;

  static void update(AppLifecycleState state) {
    final isForeground = state == AppLifecycleState.resumed;
    isAppInForeground = isForeground;
    IncomingNotificationService.setEngineAlive(isForeground);
  }
}
