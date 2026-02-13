import 'dart:async';

import 'package:flutter/foundation.dart';

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

  Future<bool> drainPendingCallActions({
    required bool Function() isDisposed,
    required bool debugMode,
    required Future<void> Function() handleIncomingCallHint,
    required bool Function() incomingRegistrationReady,
    required Future<List<dynamic>?> Function() fetchPendingCallActions,
    required void Function(String msg) log,
    required Map<String, DateTime> processedPendingCallActions,
    required Duration pendingCallActionDedupTtl,
    required bool Function(String callId) isCallAlive,
    required String? Function() currentRingingCallId,
    required CallNotificationCleanup notifCleanup,
    required Future<void> Function(String callId) answerFromNotification,
    required Future<void> Function(String callId) declineFromNotification,
  }) async {
    if (isDisposed()) return false;
    final ready = await ensureIncomingReady(
      isDisposed: isDisposed,
      handleIncomingCallHint: handleIncomingCallHint,
      incomingRegistrationReady: incomingRegistrationReady,
      log: log,
    );
    if (isDisposed()) return false;
    if (!ready) {
      log('[CALLS] drainPendingCallActions aborted: registration not ready');
      return false;
    }
    final raw = await fetchPendingCallActions();
    if (isDisposed()) return false;
    final totalPending = raw?.length ?? 0;
    log('[CALLS] drainPendingCallActions fetched count=$totalPending');
    if (raw == null || raw.isEmpty) return false;
    final now = DateTime.now();
    const ttl = Duration(seconds: 60);
    processedPendingCallActions.removeWhere(
      (_, timestamp) => now.difference(timestamp) > pendingCallActionDedupTtl,
    );
    var dedupSkipped = 0;
    var expiredDropped = 0;
    var deferredCount = 0;
    var processed = 0;
    for (final item in raw) {
      if (item is! Map) continue;
      final rawType = item['type'] ?? item['action'];
      final type = rawType?.toString().toLowerCase();
      if (type != 'answer' && type != 'decline') {
        if (kDebugMode) {
          log(
            '[CALLS] drainPendingCallActions skipping invalid action=$rawType callId=${item['callId'] ?? item['call_id']} keys=${item.keys}',
          );
        }
        continue;
      }
      final callId = (item['callId'] ?? item['call_id'])?.toString() ?? '';
      final tsValue = item['ts'] ?? item['timestamp'];
      final tsMillis = _parseTimestampMillis(tsValue);
      if (tsMillis != null &&
          now.difference(DateTime.fromMillisecondsSinceEpoch(tsMillis)) >=
              ttl) {
        expiredDropped++;
        continue;
      }
      final tsKeyRaw = tsValue?.toString() ?? '';
      final dedupKey = '$type|$callId|$tsKeyRaw';
      if (processedPendingCallActions.containsKey(dedupKey)) {
        log(
          '[CALLS] drainPendingCallActions skipping duplicate type=$type '
          'callId=$callId ts=$tsKeyRaw',
        );
        dedupSkipped++;
        continue;
      }
      processedPendingCallActions[dedupKey] = now;
      final resolvedCallId = callId.isNotEmpty
          ? callId
          : currentRingingCallId();
      if (type == 'answer') {
        processed++;
        if (resolvedCallId == null || !isCallAlive(resolvedCallId)) {
          log(
            '[CALLS] pending answer deferred: call unavailable raw=$callId resolved=$resolvedCallId',
          );
          if (resolvedCallId != null && resolvedCallId.isNotEmpty) {
            await notifCleanup.clearCallNotificationState(
              resolvedCallId,
              cancelNotification: true,
              clearPendingHint: false,
            );
          }
          processedPendingCallActions.remove(dedupKey);
          deferredCount++;
          continue;
        }
        log(
          '[CALLS] drainPendingCallActions applying answer callId=$resolvedCallId raw=$callId',
        );
        await answerFromNotification(resolvedCallId);
        log(
          '[CALLS] drainPendingCallActions applied type=answer resolvedCallId=$resolvedCallId rawCallId=$callId',
        );
      } else if (type == 'decline') {
        processed++;
        if (resolvedCallId == null || !isCallAlive(resolvedCallId)) {
          log(
            '[CALLS] pending decline deferred: call unavailable raw=$callId resolved=$resolvedCallId',
          );
          if (resolvedCallId != null && resolvedCallId.isNotEmpty) {
            await notifCleanup.clearCallNotificationState(
              resolvedCallId,
              cancelNotification: true,
              clearPendingHint: false,
            );
          }
          processedPendingCallActions.remove(dedupKey);
          deferredCount++;
          continue;
        }
        log(
          '[CALLS] drainPendingCallActions applying decline callId=$resolvedCallId raw=$callId',
        );
        await declineFromNotification(resolvedCallId);
        log(
          '[CALLS] drainPendingCallActions applied type=decline resolvedCallId=$resolvedCallId rawCallId=$callId',
        );
      }
    }
    if (debugMode) {
      final totalConsidered = processed + dedupSkipped;
      log(
        '[CALLS] drainPendingCallActions summary total=$totalConsidered '
        'processed=$processed dedupSkipped=$dedupSkipped '
        'deferredCount=$deferredCount expiredDropped=$expiredDropped',
      );
    }
    return processed > 0;
  }

  int? _parseTimestampMillis(dynamic value) {
    if (value == null) return null;
    int? parsed;
    if (value is num) {
      parsed = value.toInt();
    } else {
      final str = value.toString();
      parsed = int.tryParse(str);
    }
    if (parsed == null) return null;
    if (parsed > 0 && parsed < 1000000000000) {
      return parsed * 1000;
    }
    return parsed;
  }
}
