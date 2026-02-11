import 'package:app/features/calls/state/call_reconnect_log.dart';
import 'package:app/features/calls/state/call_reconnect_policy.dart';

abstract class ReconnectScheduleDecision {
  const ReconnectScheduleDecision._();
}

class ReconnectScheduleDecisionSkip extends ReconnectScheduleDecision {
  const ReconnectScheduleDecisionSkip({
    this.reason,
    this.inFlight = false,
    this.disposed = false,
    this.message,
  }) : super._();

  final CallReconnectScheduleBlockReason? reason;
  final bool inFlight;
  final bool disposed;
  final String? message;
}

class ReconnectScheduleDecisionAllow extends ReconnectScheduleDecision {
  const ReconnectScheduleDecisionAllow() : super._();
}

class CallReconnectCoordinator {
  CallReconnectCoordinator._();

  static ReconnectScheduleDecision decideSchedule({
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
      return const ReconnectScheduleDecisionSkip(disposed: true);
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
      return ReconnectScheduleDecisionSkip(
        reason: scheduleReason,
        message: message,
      );
    }
    if (reconnectInFlight) {
      return ReconnectScheduleDecisionSkip(
        inFlight: true,
        message: CallReconnectLog.scheduleSkipInFlight(reason),
      );
    }
    return const ReconnectScheduleDecisionAllow();
  }
}
