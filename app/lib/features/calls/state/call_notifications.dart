import 'package:flutter/foundation.dart';

import 'package:app/core/storage/fcm_storage.dart';
import 'package:app/services/incoming_notification_service.dart';

import 'call_models.dart';

// -----------------------------------------------------------------------------
// Notification cleanup helpers
// -----------------------------------------------------------------------------

class CallNotificationCleanup {
  CallNotificationCleanup({
    required this.getState,
    required this.sipToLocalCallId,
  });

  final CallState Function() getState;
  final Map<String, String> sipToLocalCallId;

  Future<CallNotificationCleanupResult> clearCallNotificationState(
    String callId, {
    bool cancelNotification = false,
    bool clearPendingHint = false,
    bool clearPendingAction = false,
  }) async {
    var clearedAction = false;
    var clearedHint = false;
    if (cancelNotification) {
      if (kDebugMode) {
        debugPrint(
          '[CALLS_NOTIF] cleanup order update->cancel->clear callId=$callId',
        );
      }
      final ids = _notificationCallIds(callId);
      if (kDebugMode) {
        debugPrint('[CALLS_NOTIF] cancelIncoming ids=$ids');
      }
      await maybeUpdateNotificationToNotRinging(callId);
      await _cancelIncomingNotificationsForCall(callId);
    }
    if (clearPendingAction) {
      try {
        final pendingAction = PendingCallAction.tryParse(
          await IncomingNotificationService.readCallAction(),
        );
        final actionCallId = pendingAction?.callId;
        if (_callIdMatches(callId, actionCallId)) {
          await IncomingNotificationService.clearCallAction();
          clearedAction = true;
        }
      } catch (_) {
        // best-effort
      }
    }
    if (clearPendingHint) {
      try {
        final pendingHint = PendingIncomingHint.tryParse(
          await FcmStorage.readPendingIncomingHint(),
        );
        final pendingCallId = pendingHint?.callId;
        final pendingCallUuid = pendingHint?.callUuid;
        if (_callIdMatches(callId, pendingCallId) ||
            _callIdMatches(callId, pendingCallUuid)) {
          await FcmStorage.clearPendingIncomingHint();
          clearedHint = true;
        }
      } catch (_) {
        // best-effort
      }
    }
    return CallNotificationCleanupResult(
      clearedAction: clearedAction,
      clearedHint: clearedHint,
    );
  }

  bool _callIdMatches(String referenceCallId, String? candidate) {
    if (candidate == null) return false;
    final localId = sipToLocalCallId.containsKey(referenceCallId)
        ? sipToLocalCallId[referenceCallId]!
        : referenceCallId;
    if (candidate == referenceCallId || candidate == localId) {
      return true;
    }
    for (final entry in sipToLocalCallId.entries) {
      if (entry.value == localId && candidate == entry.key) {
        return true;
      }
      if (entry.key == referenceCallId && candidate == entry.value) {
        return true;
      }
    }
    return false;
  }

  Set<String> _notificationCallIds(String callId) {
    final ids = <String>{};
    ids.add(callId);
    final localId = sipToLocalCallId.containsKey(callId)
        ? sipToLocalCallId[callId]!
        : callId;
    ids.add(localId);
    final sipId = _sipIdForLocal(localId);
    if (sipId != null) {
      ids.add(sipId);
    }
    return ids;
  }

  String? _sipIdForLocal(String localId) {
    for (final entry in sipToLocalCallId.entries) {
      if (entry.value == localId) {
        return entry.key;
      }
    }
    return null;
  }

  CallInfo? _callInfoForNotification(String callId) {
    final state = getState();
    final baseInfo = state.calls[callId];
    if (baseInfo != null) return baseInfo;
    final localId = sipToLocalCallId.containsKey(callId)
        ? sipToLocalCallId[callId]!
        : callId;
    final localInfo = state.calls[localId];
    if (localInfo != null) return localInfo;
    final sipId = _sipIdForLocal(localId);
    if (sipId != null) {
      return state.calls[sipId];
    }
    return null;
  }

  Future<void> maybeUpdateNotificationToNotRinging(String callId) async {
    final info = _callInfoForNotification(callId);
    if (info == null) return;
    String? payloadFrom;
    String? payloadDisplayName;
    String? payloadCallId;
    String? payloadCallUuid;
    try {
      final pendingHint = PendingIncomingHint.tryParse(
        await FcmStorage.readPendingIncomingHint(),
      );
      if (pendingHint == null) return;
      payloadFrom = pendingHint.from;
      payloadDisplayName = pendingHint.displayName;
      payloadCallId = pendingHint.callId;
      payloadCallUuid = pendingHint.callUuid;
    } catch (_) {
      // best-effort
    }
    if (payloadFrom == null || payloadFrom.isEmpty) return;
    final matchesCallId =
        payloadCallId != null &&
        payloadCallId.isNotEmpty &&
        _callIdMatches(callId, payloadCallId);
    final matchesCallUuid =
        payloadCallUuid != null &&
        payloadCallUuid.isNotEmpty &&
        _callIdMatches(callId, payloadCallUuid);
    if (!matchesCallId && !matchesCallUuid) {
      return;
    }
    String? callUuid;
    if (matchesCallUuid) {
      callUuid = payloadCallUuid;
    } else if (matchesCallId && payloadCallUuid?.isNotEmpty == true) {
      callUuid = payloadCallUuid;
    }
    final normalizedDisplay = (payloadDisplayName?.isNotEmpty == true
        ? payloadDisplayName
        : null);
    if (kDebugMode) {
      debugPrint(
        '[CALLS_NOTIF] updateNotRinging callId=$callId callUuid=${callUuid ?? '<none>'} '
        'from=$payloadFrom display=${normalizedDisplay ?? '<none>'}',
      );
    }
    try {
      await IncomingNotificationService.updateIncomingState(
        callId: callId,
        from: payloadFrom,
        displayName: normalizedDisplay,
        callUuid: callUuid,
        isRinging: false,
      );
    } catch (_) {
      // best-effort
    }
  }

  Future<void> _cancelIncomingNotificationsForCall(String callId) async {
    final ids = _notificationCallIds(callId);
    for (final id in ids) {
      try {
        final callUuid = id == callId ? null : id;
        await IncomingNotificationService.cancelIncoming(
          callId: callId,
          callUuid: callUuid,
        );
      } catch (_) {
        // best-effort
      }
    }
  }
}

// -----------------------------------------------------------------------------
// Notification cleanup result
// -----------------------------------------------------------------------------

class CallNotificationCleanupResult {
  const CallNotificationCleanupResult({
    required this.clearedAction,
    required this.clearedHint,
  });

  final bool clearedAction;
  final bool clearedHint;
}

// -----------------------------------------------------------------------------
// Pending notification payload parsing helpers
// -----------------------------------------------------------------------------

@visibleForTesting
class PendingCallAction {
  const PendingCallAction({this.callId});

  final String? callId;

  static PendingCallAction? tryParse(Map? raw) {
    if (raw == null) return null;
    final callId = raw['call_id']?.toString() ?? raw['callId']?.toString();
    return PendingCallAction(callId: callId);
  }
}

@visibleForTesting
class PendingIncomingHint {
  const PendingIncomingHint({
    this.callId,
    this.callUuid,
    this.from,
    this.displayName,
  });

  final String? callId;
  final String? callUuid;
  final String? from;
  final String? displayName;

  static PendingIncomingHint? tryParse(Map? raw) {
    if (raw == null) return null;
    final payload = raw['payload'];
    if (payload is! Map<String, dynamic>) return null;
    final rawFrom = payload['from'];
    if (rawFrom == null) return null;
    final from = rawFrom.toString().trim();
    if (from.isEmpty) return null;
    final rawDisplayName = payload['display_name'];
    final trimmedDisplayName = rawDisplayName?.toString().trim();
    final displayName =
        trimmedDisplayName != null && trimmedDisplayName.isNotEmpty
        ? trimmedDisplayName
        : null;
    final callId = payload['call_id']?.toString();
    final callUuid = payload['call_uuid']?.toString();
    return PendingIncomingHint(
      callId: callId,
      callUuid: callUuid,
      from: from,
      displayName: displayName,
    );
  }
}
