import 'package:flutter/foundation.dart';

import 'package:app/services/incoming_notification_service.dart';

class IncomingSmokeHarness {
  static const _sampleCallId = 'smoke_call';
  static const _sampleCallUuid = 'smoke_uuid';
  static const _sampleFrom = '1001';
  static const _sampleDisplayName = 'Smoke Call';

  static Future<void> showRinging() async {
    if (kDebugMode) {
      debugPrint(
        '[SMOKE] showRinging start callId=$_sampleCallId callUuid=$_sampleCallUuid from=$_sampleFrom display=$_sampleDisplayName',
      );
    }
    await IncomingNotificationService.showIncoming(
      callId: _sampleCallId,
      from: _sampleFrom,
      displayName: _sampleDisplayName,
      callUuid: _sampleCallUuid,
      isRinging: true,
    );
    if (kDebugMode) {
      debugPrint('[SMOKE] showRinging done');
    }
  }

  static Future<void> updateNotRinging() async {
    if (kDebugMode) {
      debugPrint(
        '[SMOKE] updateNotRinging start callId=$_sampleCallId callUuid=$_sampleCallUuid from=$_sampleFrom display=$_sampleDisplayName',
      );
    }
    await IncomingNotificationService.updateIncomingState(
      callId: _sampleCallId,
      from: _sampleFrom,
      displayName: _sampleDisplayName,
      callUuid: _sampleCallUuid,
      isRinging: false,
    );
    if (kDebugMode) {
      debugPrint('[SMOKE] updateNotRinging done');
    }
  }

  static Future<void> cancel() async {
    if (kDebugMode) {
      debugPrint(
        '[SMOKE] cancel start callId=$_sampleCallId callUuid=$_sampleCallUuid',
      );
    }
    await IncomingNotificationService.cancelIncoming(
      callId: _sampleCallId,
      callUuid: _sampleCallUuid,
    );
    if (kDebugMode) {
      debugPrint('[SMOKE] cancel done');
    }
  }
}
