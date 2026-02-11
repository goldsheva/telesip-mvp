import 'package:app/features/calls/state/call_reconnect_decision.dart';
import 'package:app/features/calls/state/call_reconnect_log.dart';
import 'package:app/features/calls/state/call_reconnect_policy.dart';

class CallReconnectPerformCoordinator {
  CallReconnectPerformCoordinator._();

  static ReconnectDecision decidePerform({
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
      return const ReconnectDecisionSkip(disposed: true);
    }
    if (reconnectInFlight) {
      return const ReconnectDecisionSkip(inFlight: true);
    }
    final performReason = CallReconnectPolicy.performBlockReason(
      disposed: false,
      reconnectInFlight: false,
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
      return ReconnectDecisionSkip(message: message);
    }
    return const ReconnectDecisionAllow();
  }
}
