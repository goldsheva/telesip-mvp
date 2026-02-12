import 'package:app/features/auth/state/auth_state.dart';

import 'package:app/features/calls/state/call_reconnect.dart';
import 'package:app/features/calls/state/call_reconnect_coordinator.dart';
import 'package:app/features/calls/state/call_reconnect_perform_coordinator.dart';

class CallReconnectService {
  const CallReconnectService();

  void scheduleReconnect({
    required String reason,
    required bool disposed,
    required AuthStatus authStatus,
    required String activeCallIdForLogs,
    required bool lastKnownOnline,
    required bool hasActiveCall,
    required bool reconnectInFlight,
    required bool isRegistered,
    required DateTime? lastNetworkActivityAt,
    required CallReconnectSchedulerApi reconnectScheduler,
    required void Function(String msg) log,
    required void Function(String tag) debugDumpConnectivityAndSipHealth,
    required void Function() onFire,
    required DateTime now,
  }) {
    if (disposed) return;
    final decision = CallReconnectCoordinator.decideSchedule(
      reason: reason,
      authStatusName: authStatus.name,
      activeCallId: activeCallIdForLogs,
      disposed: disposed,
      authenticated: authStatus == AuthStatus.authenticated,
      online: lastKnownOnline,
      hasActiveCall: hasActiveCall,
      reconnectInFlight: reconnectInFlight,
    );
    if (_handleReconnectDecision(
      decision: decision,
      treatInFlightAsSilent: false,
      log: log,
    )) {
      return;
    }
    reconnectScheduler.cancel();
    final delay = reconnectScheduler.currentDelay;
    final attemptNumber = reconnectScheduler.currentAttemptNumber;
    final lastNetAge = _formatLastNetAge(lastNetworkActivityAt, now);
    log(
      CallReconnectLog.scheduleScheduled(
        reason: reason,
        attemptNumber: attemptNumber,
        delayMs: delay.inMilliseconds,
        online: lastKnownOnline,
        authStatus: authStatus.name,
        registered: isRegistered,
        lastNetAge: lastNetAge,
        backoffIndex: reconnectScheduler.backoffIndex,
      ),
    );
    debugDumpConnectivityAndSipHealth('scheduleReconnect');
    reconnectScheduler.schedule(reason: reason, onFire: onFire);
  }

  Future<void> performReconnect({
    required String reason,
    required bool disposed,
    required AuthStatus authStatus,
    required String activeCallIdForLogs,
    required bool lastKnownOnline,
    required bool hasActiveCall,
    required bool reconnectInFlight,
    required void Function(String msg) log,
    required Future<bool> Function(String reason) executeReconnect,
  }) async {
    if (disposed) return;
    final performDecision = CallReconnectPerformCoordinator.decidePerform(
      reason: reason,
      authStatusName: authStatus.name,
      activeCallId: activeCallIdForLogs,
      disposed: disposed,
      reconnectInFlight: reconnectInFlight,
      online: lastKnownOnline,
      hasActiveCall: hasActiveCall,
      authenticated: authStatus == AuthStatus.authenticated,
    );
    if (_handleReconnectDecision(
      decision: performDecision,
      treatInFlightAsSilent: true,
      log: log,
    )) {
      return;
    }
    await executeReconnect(reason);
  }

  bool _handleReconnectDecision({
    required ReconnectDecision decision,
    required bool treatInFlightAsSilent,
    required void Function(String msg) log,
  }) {
    if (decision is! ReconnectDecisionSkip) return false;
    if (decision.disposed) return true;
    if (decision.inFlight) {
      if (treatInFlightAsSilent) return true;
      final message = decision.message;
      if (message != null) {
        log(message);
      }
      return true;
    }
    final message = decision.message;
    if (message != null) {
      log(message);
    }
    return true;
  }

  String _formatLastNetAge(DateTime? lastNetworkActivityAt, DateTime now) {
    if (lastNetworkActivityAt == null) return '<none>';
    final ageSeconds = now.difference(lastNetworkActivityAt).inSeconds;
    return '${ageSeconds}s';
  }
}
