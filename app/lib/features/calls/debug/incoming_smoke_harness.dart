import 'package:flutter/foundation.dart';

import 'package:app/services/incoming_notification_service.dart';

/// Manual on-device incoming-call exercise tool (debug builds only).
/// Not intended as a test harness; use this to validate notification/show/update/cancel
/// flows without a PBX. All methods are gated by `kDebugMode` to avoid release-side exposure.
class IncomingSmokeHarness {
  static const _sampleFrom = '1001';
  static const _sampleDisplayName = 'Smoke Call';

  static _RunIds _createIds() {
    final suffix = DateTime.now().millisecondsSinceEpoch % 1000000;
    return _RunIds(
      callId: 'smoke_call_$suffix',
      callUuid: 'smoke_uuid_$suffix',
    );
  }

  static Future<void> showRinging({
    String? callId,
    String? callUuid,
    String? from,
    String? displayName,
  }) async {
    final base = _createIds();
    final ids = _RunIds(
      callId: callId ?? base.callId,
      callUuid: callUuid ?? base.callUuid,
    );
    if (kDebugMode) {
      debugPrint(
        '[SMOKE ${DateTime.now().toIso8601String()}] showRinging start callId=${ids.callId} '
        'callUuid=${ids.callUuid} from=${from ?? _sampleFrom} display=${displayName ?? _sampleDisplayName}',
      );
    }
    await IncomingNotificationService.showIncoming(
      callId: ids.callId,
      from: from ?? _sampleFrom,
      displayName: displayName ?? _sampleDisplayName,
      callUuid: ids.callUuid,
      isRinging: true,
    );
    if (kDebugMode) {
      debugPrint(
        '[SMOKE ${DateTime.now().toIso8601String()}] showRinging done',
      );
    }
  }

  static Future<void> updateNotRinging({
    String? callId,
    String? callUuid,
    String? from,
    String? displayName,
  }) async {
    final base = _createIds();
    final ids = _RunIds(
      callId: callId ?? base.callId,
      callUuid: callUuid ?? base.callUuid,
    );
    if (kDebugMode) {
      debugPrint(
        '[SMOKE ${DateTime.now().toIso8601String()}] updateNotRinging start callId=${ids.callId} '
        'callUuid=${ids.callUuid} from=${from ?? _sampleFrom} display=${displayName ?? _sampleDisplayName}',
      );
    }
    await IncomingNotificationService.updateIncomingState(
      callId: ids.callId,
      from: from ?? _sampleFrom,
      displayName: displayName ?? _sampleDisplayName,
      callUuid: ids.callUuid,
      isRinging: false,
    );
    if (kDebugMode) {
      debugPrint(
        '[SMOKE ${DateTime.now().toIso8601String()}] updateNotRinging done',
      );
    }
  }

  static Future<void> cancel({String? callId, String? callUuid}) async {
    final base = _createIds();
    final ids = _RunIds(
      callId: callId ?? base.callId,
      callUuid: callUuid ?? base.callUuid,
    );
    if (kDebugMode) {
      debugPrint(
        '[SMOKE ${DateTime.now().toIso8601String()}] cancel start callId=${ids.callId} callUuid=${ids.callUuid}',
      );
    }
    await IncomingNotificationService.cancelIncoming(
      callId: ids.callId,
      callUuid: ids.callUuid,
    );
    if (kDebugMode) {
      debugPrint('[SMOKE ${DateTime.now().toIso8601String()}] cancel done');
    }
  }

  static Future<void> runSequence() async {
    const delay = Duration(milliseconds: 400);
    final ids = _createIds();
    if (kDebugMode) {
      debugPrint(
        '[SMOKE ${DateTime.now().toIso8601String()}] sequence start callId=${ids.callId} callUuid=${ids.callUuid}',
      );
    }
    await showRinging(callId: ids.callId, callUuid: ids.callUuid);
    await Future.delayed(delay);
    await updateNotRinging(callId: ids.callId, callUuid: ids.callUuid);
    await Future.delayed(delay);
    await cancel(callId: ids.callId, callUuid: ids.callUuid);
    if (kDebugMode) {
      debugPrint('[SMOKE ${DateTime.now().toIso8601String()}] sequence done');
    }
  }
}

class _RunIds {
  _RunIds({required this.callId, required this.callUuid});

  final String callId;
  final String callUuid;
}
