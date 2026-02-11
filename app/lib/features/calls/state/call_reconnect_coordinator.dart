import 'package:app/features/calls/state/call_reconnect_policy.dart';

abstract class ReconnectScheduleDecision {
  const ReconnectScheduleDecision._();
}

class ReconnectScheduleDecisionSkip extends ReconnectScheduleDecision {
  const ReconnectScheduleDecisionSkip({
    this.reason,
    this.inFlight = false,
    this.disposed = false,
  }) : super._();

  final CallReconnectScheduleBlockReason? reason;
  final bool inFlight;
  final bool disposed;
}

class ReconnectScheduleDecisionAllow extends ReconnectScheduleDecision {
  const ReconnectScheduleDecisionAllow() : super._();
}

class CallReconnectCoordinator {
  CallReconnectCoordinator._();

  static ReconnectScheduleDecision decideSchedule({
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
      return ReconnectScheduleDecisionSkip(reason: scheduleReason);
    }
    if (reconnectInFlight) {
      return const ReconnectScheduleDecisionSkip(inFlight: true);
    }
    return const ReconnectScheduleDecisionAllow();
  }
}
