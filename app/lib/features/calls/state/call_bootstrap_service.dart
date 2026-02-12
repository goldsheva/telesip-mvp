import 'dart:async';

import 'call_models.dart';
import 'call_notifications.dart';

class CallBootstrapService {
  const CallBootstrapService();

  Future<bool> ensureIncomingReady({
    required bool Function() isDisposed,
    required Future<void> Function() handleIncomingCallHint,
    required bool Function() incomingRegistrationReady,
    required void Function(String msg) log,
    Duration timeout = const Duration(seconds: 4),
  }) async {
    if (isDisposed()) return false;
    await handleIncomingCallHint();
    if (isDisposed()) return false;
    final deadline = DateTime.now().add(timeout);
    while (!incomingRegistrationReady() && DateTime.now().isBefore(deadline)) {
      if (isDisposed()) return false;
      await Future.delayed(const Duration(milliseconds: 200));
      if (isDisposed()) return false;
    }
    if (incomingRegistrationReady()) return true;
    log('[INCOMING] registration not ready after ${timeout.inSeconds}s');
    return false;
  }

  void bootstrapIfNeeded({
    required bool Function() isDisposed,
    required bool debugMode,
    required bool bootstrapDone,
    required bool bootstrapInFlight,
    required bool bootstrapScheduled,
    required CallState snapshot,
    required void Function(String msg) debugPrint,
    required String? Function() prerequisitesSkipReason,
    required void Function(bool value) setBootstrapInFlight,
    required void Function() markBootstrapDone,
    required void Function(DateTime completedAt) setBootstrapCompletedAt,
    required void Function(CallState snapshot) syncForegroundServiceState,
    required Future<void> Function() handleIncomingCallHint,
    required void Function() maybeStartHealthWatchdog,
  }) {
    if (isDisposed()) return;
    if (debugMode && bootstrapDone) {
      debugPrint('[CALLS] bootstrapIfNeeded skip already done');
      return;
    }
    if (debugMode) {
      debugPrint(
        '[CALLS] bootstrapIfNeeded enter scheduled=$bootstrapScheduled '
        'done=$bootstrapDone active=${snapshot.activeCallId} '
        'status=${snapshot.activeCall?.status}',
      );
    }
    if (bootstrapDone) return;
    if (bootstrapInFlight) {
      if (debugMode) {
        debugPrint('[CALLS] bootstrapIfNeeded skip already in-flight');
      }
      return;
    }
    setBootstrapInFlight(true);
    try {
      final skipReason = prerequisitesSkipReason();
      if (skipReason != null) {
        debugPrint('[CALLS] bootstrapIfNeeded skip: $skipReason');
        return;
      }
      markBootstrapDone();
      setBootstrapCompletedAt(DateTime.now());
      syncForegroundServiceState(snapshot);
      unawaited(handleIncomingCallHint());
      maybeStartHealthWatchdog();
    } finally {
      setBootstrapInFlight(false);
    }
  }

  Future<void> drainPendingCallActions({
    required bool Function() isDisposed,
    required bool debugMode,
    required Future<void> Function() handleIncomingCallHint,
    required bool Function() incomingRegistrationReady,
    required Future<List<dynamic>?> Function() fetchPendingCallActions,
    required void Function(String msg) log,
    required Map<String, DateTime> processedPendingCallActions,
    required Duration pendingCallActionDedupTtl,
    required bool Function(String callId) isCallAlive,
    required CallNotificationCleanup notifCleanup,
    required Future<void> Function(String callId) answerFromNotification,
    required Future<void> Function(String callId) declineFromNotification,
  }) async {
    if (isDisposed()) return;
    final ready = await ensureIncomingReady(
      isDisposed: isDisposed,
      handleIncomingCallHint: handleIncomingCallHint,
      incomingRegistrationReady: incomingRegistrationReady,
      log: log,
    );
    if (isDisposed()) return;
    if (!ready) {
      log('[CALLS] drainPendingCallActions aborted: registration not ready');
      return;
    }
    final raw = await fetchPendingCallActions();
    if (isDisposed()) return;
    if (raw == null || raw.isEmpty) return;
    final now = DateTime.now();
    processedPendingCallActions.removeWhere(
      (_, timestamp) => now.difference(timestamp) > pendingCallActionDedupTtl,
    );
    var dedupSkipped = 0;
    var unknownCleared = 0;
    var processed = 0;
    for (final item in raw) {
      if (item is! Map) continue;
      final type = item['type']?.toString();
      final callId = item['callId']?.toString();
      if (type == null || callId == null) continue;
      final tsKey = item['ts']?.toString() ?? '';
      final dedupKey = '$type|$callId|$tsKey';
      if (processedPendingCallActions.containsKey(dedupKey)) {
        log(
          '[CALLS] drainPendingCallActions skipping duplicate type=$type '
          'callId=$callId ts=$tsKey',
        );
        dedupSkipped++;
        continue;
      }
      processedPendingCallActions[dedupKey] = now;
      if (type == 'answer') {
        processed++;
        if (!isCallAlive(callId)) {
          log('[CALLS] pending answer for unknown call $callId, clearing');
          await notifCleanup.clearCallNotificationState(
            callId,
            cancelNotification: true,
            clearPendingAction: true,
            clearPendingHint: true,
          );
          unknownCleared++;
          continue;
        }
        await answerFromNotification(callId);
      } else if (type == 'decline') {
        processed++;
        if (!isCallAlive(callId)) {
          log('[CALLS] pending decline for unknown call $callId, clearing');
          await notifCleanup.clearCallNotificationState(
            callId,
            cancelNotification: true,
            clearPendingAction: true,
            clearPendingHint: true,
          );
          unknownCleared++;
          continue;
        }
        await declineFromNotification(callId);
      }
    }
    if (debugMode) {
      final totalConsidered = processed + dedupSkipped;
      log(
        '[CALLS] drainPendingCallActions summary total=$totalConsidered '
        'processed=$processed dedupSkipped=$dedupSkipped '
        'unknownCleared=$unknownCleared',
      );
    }
  }
}
