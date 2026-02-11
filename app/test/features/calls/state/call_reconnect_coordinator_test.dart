import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/calls/state/call_reconnect_coordinator.dart';
import 'package:app/features/calls/state/call_reconnect_policy.dart';

void main() {
  group('CallReconnectCoordinator.decideSchedule', () {
    test('skips when disposed', () {
      final decision = CallReconnectCoordinator.decideSchedule(
        disposed: true,
        authenticated: true,
        online: true,
        hasActiveCall: false,
        reconnectInFlight: false,
      );
      expect(decision, isA<ReconnectScheduleDecisionSkip>());
      final skip = decision as ReconnectScheduleDecisionSkip;
      expect(skip.disposed, isTrue);
    });

    test('skips for authentication/offline/active-call reasons', () {
      final unauthenticated = CallReconnectCoordinator.decideSchedule(
        disposed: false,
        authenticated: false,
        online: true,
        hasActiveCall: false,
        reconnectInFlight: false,
      );
      expect(unauthenticated, isA<ReconnectScheduleDecisionSkip>());
      expect(
        (unauthenticated as ReconnectScheduleDecisionSkip).reason,
        CallReconnectScheduleBlockReason.notAuthenticated,
      );

      final offline = CallReconnectCoordinator.decideSchedule(
        disposed: false,
        authenticated: true,
        online: false,
        hasActiveCall: false,
        reconnectInFlight: false,
      );
      expect(offline, isA<ReconnectScheduleDecisionSkip>());
      expect(
        (offline as ReconnectScheduleDecisionSkip).reason,
        CallReconnectScheduleBlockReason.offline,
      );

      final activeCall = CallReconnectCoordinator.decideSchedule(
        disposed: false,
        authenticated: true,
        online: true,
        hasActiveCall: true,
        reconnectInFlight: false,
      );
      expect(activeCall, isA<ReconnectScheduleDecisionSkip>());
      expect(
        (activeCall as ReconnectScheduleDecisionSkip).reason,
        CallReconnectScheduleBlockReason.hasActiveCall,
      );
    });

    test('skips when reconnect already in flight', () {
      final decision = CallReconnectCoordinator.decideSchedule(
        disposed: false,
        authenticated: true,
        online: true,
        hasActiveCall: false,
        reconnectInFlight: true,
      );
      expect(decision, isA<ReconnectScheduleDecisionSkip>());
      final skip = decision as ReconnectScheduleDecisionSkip;
      expect(skip.inFlight, isTrue);
    });

    test('allows when no blockers', () {
      final decision = CallReconnectCoordinator.decideSchedule(
        disposed: false,
        authenticated: true,
        online: true,
        hasActiveCall: false,
        reconnectInFlight: false,
      );
      expect(decision, isA<ReconnectScheduleDecisionAllow>());
    });
  });
}
