import 'dart:developer';

import 'package:permission_handler/permission_handler.dart';

class PermissionsService {
  PermissionsService._();

  static Future<bool> ensureMicrophonePermission() async {
    return _ensurePermission(
      Permission.microphone,
      'Microphone permission is required to make calls.',
    );
  }

  static Future<bool> ensureNotificationsPermission() async {
    return _ensurePermission(
      Permission.notification,
      'Notification permission is required to receive incoming calls.',
    );
  }

  static Future<bool> _ensurePermission(
    Permission permission,
    String message,
  ) async {
    final status = await permission.status;
    if (status.isGranted) return true;

    final requestResult = await permission.request();
    if (requestResult.isGranted) {
      return true;
    }

    if (requestResult.isPermanentlyDenied) {
      await openAppSettings();
    }

    log('[PermissionsService] Permission denied: $message');
    return false;
  }
}
