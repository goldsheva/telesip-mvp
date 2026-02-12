import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:app/features/calls/incoming/incoming_wake_coordinator.dart';
import 'package:app/features/calls/state/call_notifier.dart';
import 'package:app/services/incoming_notification_service.dart';

class IncomingCallCoordinator {
  IncomingCallCoordinator(WidgetRef ref) : _ref = ref;

  final WidgetRef _ref;
  bool _processing = false;
  DateTime? _lastIncomingActivityAt;

  DateTime? get lastIncomingActivityAt => _lastIncomingActivityAt;

  void clearLastIncomingActivity() {
    _lastIncomingActivityAt = null;
  }

  Future<void> processIncomingActivity() async {
    if (_processing) return;
    _processing = true;
    try {
      final handled = await _ref
          .read(incomingWakeCoordinatorProvider)
          .checkPendingHint();
      if (handled) {
        _lastIncomingActivityAt = DateTime.now();
      }
      await _handlePendingCallAction();
    } finally {
      _processing = false;
    }
  }

  Future<void> _handlePendingCallAction() async {
    final rawAction = await IncomingNotificationService.readCallAction();
    if (rawAction == null) return;
    _lastIncomingActivityAt = DateTime.now();
    final callId =
        rawAction['call_id']?.toString() ?? rawAction['callId']?.toString();
    final action = (rawAction['action'] ?? rawAction['type'])?.toString();
    final timestampMillis = _timestampToMillis(
      rawAction['timestamp'] ?? rawAction['ts'],
    );
    if (callId == null || action == null || timestampMillis == null) {
      await IncomingNotificationService.clearCallAction();
      return;
    }
    final actionAge = DateTime.now().difference(
      DateTime.fromMillisecondsSinceEpoch(timestampMillis),
    );
    if (actionAge > const Duration(seconds: 30)) {
      await IncomingNotificationService.clearCallAction();
      return;
    }

    final callState = _ref.read(callControllerProvider);
    final callInfo = callState.calls[callId];
    if (callInfo == null) {
      debugPrint('[CALLS] pending action ignored: no call for callId=$callId');
      await IncomingNotificationService.clearCallAction();
      return;
    }
    if (callInfo.status == CallStatus.ended) {
      debugPrint('[CALLS] pending action ignored: call ended callId=$callId');
      await IncomingNotificationService.clearCallAction();
      return;
    }
    if (callState.activeCallId != callId) {
      debugPrint(
        '[CALLS] pending action ignored: active=${callState.activeCallId} callId=$callId',
      );
      await IncomingNotificationService.clearCallAction();
      return;
    }

    final notifier = _ref.read(callControllerProvider.notifier);
    var executed = false;
    if (action == 'answer') {
      await notifier.answerFromNotification(callId);
      executed = true;
    } else if (action == 'decline') {
      await notifier.declineFromNotification(callId);
      executed = true;
    } else {
      await IncomingNotificationService.clearCallAction();
      return;
    }

    if (executed) {
      await IncomingNotificationService.clearCallAction();
    }
  }

  int? _timestampToMillis(Object? value) {
    if (value is int) return value;
    if (value is double) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }
}
