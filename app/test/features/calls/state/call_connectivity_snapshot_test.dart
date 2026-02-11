import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/calls/state/call_connectivity_snapshot.dart';

void main() {
  group('CallConnectivitySnapshot.format', () {
    test('formats full snapshot with active call', () {
      final result = CallConnectivitySnapshot.format(
        tag: 'net-online',
        authStatus: 'authenticated',
        online: true,
        bootstrapScheduled: true,
        bootstrapDone: false,
        bootstrapInFlight: false,
        lastRegistrationState: 'registered',
        lastNetAge: '5s',
        healthTimerActive: true,
        reconnectTimerActive: false,
        reconnectInFlight: false,
        backoffIndex: 2,
        activeCallId: '123',
        activeCallStatus: 'CallStatus.connected',
        registered: true,
        stateRegistered: false,
      );

      expect(
        result,
        '[CALLS_CONN] net-online '
        'authStatus=authenticated '
        'online=true '
        'scheduled=true '
        'done=false '
        'inFlight=false '
        'registered=true '
        'stateRegistered=false '
        'lastRegistrationState=registered '
        'lastNetAge=5s '
        'healthTimer=true '
        'reconnectTimer=false '
        'reconnectInFlight=false '
        'backoffIndex=2 '
        'active=123 '
        'status=CallStatus.connected',
      );
    });
  });

  group('CallConnectivitySnapshot.formatShort', () {
    test('formats short snapshot without active call', () {
      final result = CallConnectivitySnapshot.formatShort(
        tag: 'net-online',
        authStatus: 'unknown',
        online: false,
        bootstrapScheduled: false,
        bootstrapDone: true,
        bootstrapInFlight: true,
        lastNetAge: '<none>',
        backoffIndex: 0,
        activeCallId: '<none>',
        activeCallStatus: '<none>',
        registeredAt: false,
      );

      expect(
        result,
        '[CALLS_CONN] net-online '
        'authStatus=unknown '
        'online=false '
        'scheduled=false '
        'done=true '
        'inFlight=true '
        'active=<none> '
        'status=<none> '
        'lastNetAge=<none> '
        'backoffIndex=0 '
        'registeredAt=false',
      );
    });
  });
}
