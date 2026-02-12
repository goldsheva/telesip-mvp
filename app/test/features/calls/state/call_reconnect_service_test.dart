import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/auth/state/auth_state.dart';
import 'package:app/features/calls/state/call_reconnect.dart';
import 'package:app/features/calls/state/call_reconnect_service.dart';

final now = DateTime(2024, 1, 1, 0, 0, 30);

void main() {
  group('CallReconnectService.scheduleReconnect', () {
    test('logs skip when offline', () {
      final logs = <String>[];
      final scheduler = _FakeScheduler();
      const service = CallReconnectService();

      service.scheduleReconnect(
        reason: 'reason',
        disposed: false,
        authStatus: AuthStatus.authenticated,
        activeCallIdForLogs: '<none>',
        lastKnownOnline: false,
        hasActiveCall: false,
        reconnectInFlight: false,
        isRegistered: false,
        lastNetworkActivityAt: null,
        reconnectScheduler: scheduler,
        log: logs.add,
        debugDumpConnectivityAndSipHealth: (_) {},
        onFire: () {},
        now: DateTime(2024),
      );

      expect(logs, [CallReconnectLog.scheduleSkipOffline('reason')]);
      expect(scheduler.cancelCalled, isFalse);
      expect(scheduler.scheduleCalled, isFalse);
    });

    test('logs scheduler delay and attempt when scheduling', () {
      final logs = <String>[];
      final scheduler = _FakeScheduler()
        ..fakeAttemptNumber = 7
        ..fakeDelay = const Duration(milliseconds: 1500)
        ..fakeBackoffIndex = 3;
      const service = CallReconnectService();

      service.scheduleReconnect(
        reason: 'reason',
        disposed: false,
        authStatus: AuthStatus.authenticated,
        activeCallIdForLogs: 'call-id',
        lastKnownOnline: true,
        hasActiveCall: false,
        reconnectInFlight: false,
        isRegistered: true,
        lastNetworkActivityAt: now.subtract(const Duration(seconds: 10)),
        reconnectScheduler: scheduler,
        log: logs.add,
        debugDumpConnectivityAndSipHealth: (_) {},
        onFire: () {},
        now: now,
      );

      final expected = CallReconnectLog.scheduleScheduled(
        reason: 'reason',
        attemptNumber: 7,
        delayMs: 1500,
        online: true,
        authStatus: AuthStatus.authenticated.name,
        registered: true,
        lastNetAge: '10s',
        backoffIndex: 3,
      );
      expect(logs, [expected]);
      expect(scheduler.cancelCalled, isTrue);
      expect(scheduler.scheduleCalled, isTrue);
      expect(scheduler.scheduledReason, 'reason');
    });
  });

  group('CallReconnectService.performReconnect', () {
    test('logs skip when offline', () async {
      final logs = <String>[];
      var executed = false;
      const service = CallReconnectService();

      await service.performReconnect(
        reason: 'reason',
        disposed: false,
        authStatus: AuthStatus.authenticated,
        activeCallIdForLogs: '<none>',
        lastKnownOnline: false,
        hasActiveCall: false,
        reconnectInFlight: false,
        log: logs.add,
        executeReconnect: (_) async {
          executed = true;
          return true;
        },
      );

      expect(logs, [CallReconnectLog.reconnectSkipOffline('reason')]);
      expect(executed, isFalse);
    });

    test('calls executeReconnect when allowed', () async {
      final logs = <String>[];
      var executedReason = '';
      const service = CallReconnectService();

      await service.performReconnect(
        reason: 'reason',
        disposed: false,
        authStatus: AuthStatus.authenticated,
        activeCallIdForLogs: 'active-call',
        lastKnownOnline: true,
        hasActiveCall: false,
        reconnectInFlight: false,
        log: logs.add,
        executeReconnect: (receivedReason) async {
          executedReason = receivedReason;
          return true;
        },
      );

      expect(logs, isEmpty);
      expect(executedReason, 'reason');
    });
  });
}

class _FakeScheduler implements CallReconnectSchedulerApi {
  _FakeScheduler();

  bool cancelCalled = false;
  bool scheduleCalled = false;
  String? scheduledReason;
  void Function()? scheduledOnFire;
  Duration fakeDelay = const Duration(seconds: 1);
  int fakeAttemptNumber = 1;
  int fakeBackoffIndex = 0;

  @override
  void cancel() => cancelCalled = true;

  @override
  Duration get currentDelay => fakeDelay;

  @override
  int get currentAttemptNumber => fakeAttemptNumber;

  @override
  int get backoffIndex => fakeBackoffIndex;

  @override
  void schedule({required String reason, required void Function() onFire}) {
    scheduleCalled = true;
    scheduledReason = reason;
    scheduledOnFire = onFire;
  }
}
