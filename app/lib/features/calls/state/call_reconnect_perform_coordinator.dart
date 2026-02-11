import 'package:app/features/calls/state/call_reconnect_log.dart';
import 'package:app/features/calls/state/call_reconnect_policy.dart';

abstract class ReconnectPerformDecision {
  const ReconnectPerformDecision._();
}

class ReconnectPerformDecisionSkip extends ReconnectPerformDecision {
  const ReconnectPerformDecisionSkip({
    this.reason,
    this.inFlight = false,
    this.disposed = false,
    this.message,
  }) : super._();

  final CallReconnectPerformBlockReason? reason;
  final bool inFlight;
  final bool disposed;
  final String? message;
}

class ReconnectPerformDecisionAllow extends ReconnectPerformDecision {
  const ReconnectPerformDecisionAllow() : super._();
}

class CallReconnectPerformCoordinator {
  CallReconnectPerformCoordinator._();

  static ReconnectPerformDecision decidePerform({
    required String reason,
    required String authStatusName,
    required String activeCallId,
    required bool disposed,
    required bool reconnectInFlight,
    required bool online,
    required bool hasActiveCall,
    required bool authenticated,
  }) {
    if (disposed) {
      return const ReconnectPerformDecisionSkip(disposed: true);
    }
    if (reconnectInFlight) {
      return const ReconnectPerformDecisionSkip(inFlight: true);
    }
    final performReason = CallReconnectPolicy.performBlockReason(
      disposed: disposed,
      reconnectInFlight: reconnectInFlight,
      lastKnownOnline: online,
      hasActiveCall: hasActiveCall,
      authenticated: authenticated,
    );
    if (performReason != null) {
      String? message;
      switch (performReason) {
        case CallReconnectPerformBlockReason.disposed:
        case CallReconnectPerformBlockReason.inFlight:
          message = null;
          break;
        case CallReconnectPerformBlockReason.offline:
          message = CallReconnectLog.reconnectSkipOffline(reason);
          break;
        case CallReconnectPerformBlockReason.hasActiveCall:
          message = CallReconnectLog.reconnectSkipHasActiveCall(
            reason,
            activeCallId,
          );
          break;
        case CallReconnectPerformBlockReason.notAuthenticated:
          message = CallReconnectLog.reconnectSkipNotAuthenticated(
            reason,
            authStatusName,
          );
          break;
      }
      return ReconnectPerformDecisionSkip(
        reason: performReason,
        message: message,
      );
    }
    return const ReconnectPerformDecisionAllow();
  }
}
