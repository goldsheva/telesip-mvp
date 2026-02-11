import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/calls/state/call_reconnect_log.dart';

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

    test('reconnect failed string includes error', () {
      expect(
        CallReconnectLog.reconnectFailed('boom'),
        '[CALLS_CONN] reconnect failed: boom',
      );
    });
  });
}
