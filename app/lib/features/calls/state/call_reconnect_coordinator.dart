import 'package:app/features/calls/state/call_reconnect_decision.dart';
import 'package:app/features/calls/state/call_reconnect_log.dart';
import 'package:app/features/calls/state/call_reconnect_policy.dart';

class CallReconnectCoordinator {
  CallReconnectCoordinator._();

  static ReconnectDecision decideSchedule({
    required String reason,
    required String authStatusName,
    required String activeCallId,
    required bool disposed,
    required bool authenticated,
    required bool online,
    required bool hasActiveCall,
    required bool reconnectInFlight,
  }) {
    if (disposed) {
      return const ReconnectDecisionSkip(disposed: true);
    }
    final scheduleReason = CallReconnectPolicy.scheduleBlockReason(
      lastKnownOnline: online,
      hasActiveCall: hasActiveCall,
      authenticated: authenticated,
    );
    if (scheduleReason != null) {
      String message;
      switch (scheduleReason) {
        case CallReconnectScheduleBlockReason.notAuthenticated:
          message = CallReconnectLog.scheduleSkipNotAuthenticated(
            reason,
            authStatusName,
          );
          break;
        case CallReconnectScheduleBlockReason.offline:
          message = CallReconnectLog.scheduleSkipOffline(reason);
          break;
        case CallReconnectScheduleBlockReason.hasActiveCall:
          message = CallReconnectLog.scheduleSkipHasActiveCall(
            reason,
            activeCallId,
          );
          break;
      }
      return ReconnectDecisionSkip(message: message);
    }
    if (reconnectInFlight) {
      return ReconnectDecisionSkip(
        inFlight: true,
        message: CallReconnectLog.scheduleSkipInFlight(reason),
      );
    }
    return const ReconnectDecisionAllow();
  }
}
