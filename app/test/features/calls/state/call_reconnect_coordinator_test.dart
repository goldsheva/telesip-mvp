import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/calls/state/call_reconnect_coordinator.dart';
import 'package:app/features/calls/state/call_reconnect_decision.dart';
import 'package:app/features/calls/state/call_reconnect_log.dart';

void main() {
  group('CallReconnectCoordinator.decideSchedule', () {
    test('skips when disposed', () {
      final decision = CallReconnectCoordinator.decideSchedule(
        reason: 'reason',
        authStatusName: 'auth',
        activeCallId: '<active>',
        disposed: true,
        authenticated: true,
        online: true,
        hasActiveCall: false,
        reconnectInFlight: false,
      );
      expect(decision, isA<ReconnectDecisionSkip>());
      final skip = decision as ReconnectDecisionSkip;
      expect(skip.disposed, isTrue);
      expect(skip.message, isNull);
    });

    test('skips for authentication/offline/active-call reasons', () {
      final unauthenticated = CallReconnectCoordinator.decideSchedule(
        reason: 'reason',
        authStatusName: 'auth',
        activeCallId: '<active>',
        disposed: false,
        authenticated: false,
        online: true,
        hasActiveCall: false,
        reconnectInFlight: false,
      );
      expect(unauthenticated, isA<ReconnectDecisionSkip>());
      final unauthenticatedSkip = unauthenticated as ReconnectDecisionSkip;
      expect(
        unauthenticatedSkip.message,
        CallReconnectLog.scheduleSkipNotAuthenticated('reason', 'auth'),
      );

      final offline = CallReconnectCoordinator.decideSchedule(
        reason: 'reason',
        authStatusName: 'auth',
        activeCallId: '<active>',
        disposed: false,
        authenticated: true,
        online: false,
        hasActiveCall: false,
        reconnectInFlight: false,
      );
      expect(offline, isA<ReconnectDecisionSkip>());
      final offlineSkip = offline as ReconnectDecisionSkip;
      expect(
        offlineSkip.message,
        CallReconnectLog.scheduleSkipOffline('reason'),
      );

      final activeCall = CallReconnectCoordinator.decideSchedule(
        reason: 'reason',
        authStatusName: 'auth',
        activeCallId: '<active>',
        disposed: false,
        authenticated: true,
        online: true,
        hasActiveCall: true,
        reconnectInFlight: false,
      );
      expect(activeCall, isA<ReconnectDecisionSkip>());
      final activeCallSkip = activeCall as ReconnectDecisionSkip;
      expect(
        activeCallSkip.message,
        CallReconnectLog.scheduleSkipHasActiveCall('reason', '<active>'),
      );
    });

    test('skips when reconnect already in flight', () {
      final decision = CallReconnectCoordinator.decideSchedule(
        reason: 'reason',
        authStatusName: 'auth',
        activeCallId: '<active>',
        disposed: false,
        authenticated: true,
        online: true,
        hasActiveCall: false,
        reconnectInFlight: true,
      );
      expect(decision, isA<ReconnectDecisionSkip>());
      final skip = decision as ReconnectDecisionSkip;
      expect(skip.inFlight, isTrue);
      expect(skip.message, CallReconnectLog.scheduleSkipInFlight('reason'));
    });

    test('allows when no blockers', () {
      final decision = CallReconnectCoordinator.decideSchedule(
        reason: 'reason',
        authStatusName: 'auth',
        activeCallId: '<active>',
        disposed: false,
        authenticated: true,
        online: true,
        hasActiveCall: false,
        reconnectInFlight: false,
      );
      expect(decision, isA<ReconnectDecisionAllow>());
    });
  });
}
