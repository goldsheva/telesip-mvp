import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/calls/state/call_reconnect_coordinator.dart';
import 'package:app/features/calls/state/call_reconnect_log.dart';
import 'package:app/features/calls/state/call_reconnect_policy.dart';

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
      expect(decision, isA<ReconnectScheduleDecisionSkip>());
      final skip = decision as ReconnectScheduleDecisionSkip;
      expect(skip.disposed, isTrue);
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
      expect(unauthenticated, isA<ReconnectScheduleDecisionSkip>());
      final unauthenticatedSkip =
          unauthenticated as ReconnectScheduleDecisionSkip;
      expect(
        unauthenticatedSkip.reason,
        CallReconnectScheduleBlockReason.notAuthenticated,
      );
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
      expect(offline, isA<ReconnectScheduleDecisionSkip>());
      final offlineSkip = offline as ReconnectScheduleDecisionSkip;
      expect(offlineSkip.reason, CallReconnectScheduleBlockReason.offline);
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
      expect(activeCall, isA<ReconnectScheduleDecisionSkip>());
      final activeCallSkip = activeCall as ReconnectScheduleDecisionSkip;
      expect(
        activeCallSkip.reason,
        CallReconnectScheduleBlockReason.hasActiveCall,
      );
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
      expect(decision, isA<ReconnectScheduleDecisionSkip>());
      final skip = decision as ReconnectScheduleDecisionSkip;
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
      expect(decision, isA<ReconnectScheduleDecisionAllow>());
    });
  });
}
