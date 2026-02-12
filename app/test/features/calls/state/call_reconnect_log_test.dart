import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/calls/state/call_reconnect.dart';

void main() {
  group('CallReconnectLog', () {
    test('schedule skip not authenticated string', () {
      expect(
        CallReconnectLog.scheduleSkipNotAuthenticated(
          'reason',
          'AuthStatus.unknown',
        ),
        '[CALLS_CONN] scheduleReconnect skip reason=reason authStatus=AuthStatus.unknown',
      );
    });

    test('schedule scheduled string includes all fields', () {
      expect(
        CallReconnectLog.scheduleScheduled(
          reason: 'attempt',
          attemptNumber: 2,
          delayMs: 100,
          online: true,
          authStatus: 'AuthStatus.authenticated',
          registered: false,
          lastNetAge: '5s',
          backoffIndex: 1,
        ),
        '[CALLS_CONN] scheduleReconnect reason=attempt attempt=2 delayMs=100 online=true authStatus=AuthStatus.authenticated registered=false lastNetAge=5s backoffIndex=1',
      );
    });

    test('schedule skip offline string', () {
      expect(
        CallReconnectLog.scheduleSkipOffline('reason'),
        '[CALLS_CONN] scheduleReconnect skip reason=reason online=false',
      );
    });

    test('schedule skip has active call string', () {
      expect(
        CallReconnectLog.scheduleSkipHasActiveCall('reason', 'callId'),
        '[CALLS_CONN] scheduleReconnect skip reason=reason activeCallId=callId',
      );
    });

    test('schedule skip in flight string', () {
      expect(
        CallReconnectLog.scheduleSkipInFlight('reason'),
        '[CALLS_CONN] scheduleReconnect skip reason=reason inFlight=true',
      );
    });

    test('reconnect failed string includes error', () {
      expect(
        CallReconnectLog.reconnectFailed('boom'),
        '[CALLS_CONN] reconnect failed: boom',
      );
    });

    test('reconnect skip offline string', () {
      expect(
        CallReconnectLog.reconnectSkipOffline('reason'),
        '[CALLS_CONN] reconnect skip reason=reason online=false',
      );
    });

    test('reconnect skip has active call string', () {
      expect(
        CallReconnectLog.reconnectSkipHasActiveCall('reason', 'callId'),
        '[CALLS_CONN] reconnect skip reason=reason activeCallId=callId',
      );
    });

    test('reconnect skip not authenticated string', () {
      expect(
        CallReconnectLog.reconnectSkipNotAuthenticated(
          'reason',
          'AuthStatus.unknown',
        ),
        '[CALLS_CONN] reconnect skip reason=reason authStatus=AuthStatus.unknown',
      );
    });

    test('reconnect skip missing user string', () {
      expect(
        CallReconnectLog.reconnectSkipMissingUser('reason'),
        '[CALLS_CONN] reconnect skip reason=reason missing_user',
      );
    });

    test('reconnect fired string', () {
      expect(
        CallReconnectLog.reconnectFired('reason'),
        '[CALLS_CONN] reconnect fired reason=reason',
      );
    });
  });
}
