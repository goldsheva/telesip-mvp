import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/calls/state/call_connectivity_debug_dumper.dart';
import 'package:app/features/calls/state/call_connectivity_snapshot.dart';

void main() {
  const dumper = CallConnectivityDebugDumper();

  group('CallConnectivityDebugDumper.dumpShort', () {
    test('uses <none> labels when no activity or active call status', () {
      final logs = <String>[];
      dumper.dumpShort(
        disposed: false,
        kDebugModeEnabled: true,
        tag: 'test',
        authStatusName: 'authenticated',
        online: true,
        bootstrapScheduled: false,
        bootstrapDone: false,
        bootstrapInFlight: false,
        lastNetworkActivityAt: null,
        backoffIndex: 1,
        activeCallId: null,
        activeCallStatus: null,
        lastSipRegisteredAt: null,
        log: logs.add,
      );

      expect(logs, hasLength(1));
      final log = logs.first;
      final expected = CallConnectivitySnapshot.formatShort(
        tag: 'test',
        authStatus: 'authenticated',
        online: true,
        bootstrapScheduled: false,
        bootstrapDone: false,
        bootstrapInFlight: false,
        lastNetAge: '<none>',
        backoffIndex: 1,
        activeCallId: '<none>',
        activeCallStatus: '<none>',
        registeredAt: false,
      );

      expect(log, expected);
    });

    test('reports elapsed seconds plus active call details when provided', () {
      final logs = <String>[];
      final now = DateTime.now();
      final lastNetworkActivityAt = now.subtract(const Duration(seconds: 123));
      dumper.dumpShort(
        disposed: false,
        kDebugModeEnabled: true,
        tag: 'test',
        authStatusName: 'authenticated',
        online: false,
        bootstrapScheduled: true,
        bootstrapDone: true,
        bootstrapInFlight: false,
        lastNetworkActivityAt: lastNetworkActivityAt,
        backoffIndex: 2,
        activeCallId: 'active-call',
        activeCallStatus: const _FakeStatus('ready'),
        lastSipRegisteredAt: now,
        log: logs.add,
      );

      expect(logs, hasLength(1));
      final log = logs.first;
      final ageMatch = RegExp(r'lastNetAge=(\d+)s').firstMatch(log);
      expect(ageMatch, isNotNull);
      final ageSeconds = int.parse(ageMatch!.group(1)!);
      expect(ageSeconds, inInclusiveRange(122, 124));
      expect(log, contains('ReadyStatus(ready)'));
      expect(log, contains('registeredAt=true'));
      expect(log, contains('active-call'));
    });

    test('skips logging when debug mode disabled', () {
      final logs = <String>[];
      dumper.dumpShort(
        disposed: false,
        kDebugModeEnabled: false,
        tag: 'test',
        authStatusName: 'authenticated',
        online: true,
        bootstrapScheduled: false,
        bootstrapDone: false,
        bootstrapInFlight: false,
        lastNetworkActivityAt: null,
        backoffIndex: 0,
        activeCallId: null,
        activeCallStatus: null,
        lastSipRegisteredAt: null,
        log: logs.add,
      );

      expect(logs, isEmpty);
    });

    test('skips logging when disposed', () {
      final logs = <String>[];
      dumper.dumpShort(
        disposed: true,
        kDebugModeEnabled: true,
        tag: 'test',
        authStatusName: 'authenticated',
        online: true,
        bootstrapScheduled: false,
        bootstrapDone: false,
        bootstrapInFlight: false,
        lastNetworkActivityAt: null,
        backoffIndex: 0,
        activeCallId: null,
        activeCallStatus: null,
        lastSipRegisteredAt: null,
        log: logs.add,
      );

      expect(logs, isEmpty);
    });
  });
}

class _FakeStatus {
  const _FakeStatus(this.detail);

  final String detail;

  @override
  String toString() => 'ReadyStatus($detail)';
}
