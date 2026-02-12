import 'dart:developer';

import 'package:permission_handler/permission_handler.dart';

typedef AuthorizationStatus = PermissionStatus;

class PermissionsService {
  PermissionsService._();

  static Future<AuthorizationStatus> ensureNotificationsPermission({
    bool requestIfNeeded = true,
  }) async {
    final permission = Permission.notification;
    final status = await permission.status;
    if (status.isGranted) return status;
    if (!requestIfNeeded) {
      return status;
    }
    final result = await _requestPermission(permission);
    return result;
  }

  static Future<bool> ensureMicrophonePermission({
    bool requestIfNeeded = true,
  }) async {
    final permission = Permission.microphone;
    final status = await permission.status;
    if (status.isGranted) return true;
    if (!requestIfNeeded) {
      return status.isGranted;
    }
    final result = await _requestPermission(permission);
    return result.isGranted;
  }

  static final Map<Permission, Future<PermissionStatus>> _pendingRequests = {};
  static Future<PermissionStatus> _requestPermission(
    Permission permission,
  ) async {
    final existing = _pendingRequests[permission];
    if (existing != null) {
      log(
        '[PermissionsService] ${permission.value} request deduped (in-flight)',
      );
      return existing;
    }
    log('[PermissionsService] ${permission.value} queued');
    final future = _serial(() async {
      log('[PermissionsService] ${permission.value} start');
      final status = await permission.request();
      log('[PermissionsService] ${permission.value} done status=$status');
      if (status.isPermanentlyDenied) {
        await openAppSettings();
      }
      return status;
    });
    _pendingRequests[permission] = future;
    future.whenComplete(() => _pendingRequests.remove(permission));
    return future;
  }

  static Future<T> _serial<T>(Future<T> Function() op) {
    final next = _queue.then((_) => op());
    _queue = next.then((_) => null).catchError((_) => null);
    return next;
  }

  static Future<void> _queue = Future.value();
}
