import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/calls/state/call_reconnect_executor.dart';
import 'package:app/features/sip_users/models/pbx_sip_user.dart';

void main() {
  group('CallReconnectExecutor', () {
    test('returns false when disposed before run', () async {
      final logs = <String>[];
      final executor = CallReconnectExecutor(
        isDisposed: () => true,
        log: (message) => logs.add(message),
      );
      final result = await executor.reconnect(
        reason: 'test',
        reconnectUser: const PbxSipUser(
          pbxSipUserId: 1,
          userId: 1,
          sipLogin: 'user',
          sipPassword: 'pass',
          dialplanId: 0,
          dongleId: null,
          pbxSipConnections: [],
        ),
        ensureRegistered: (_) async {},
      );
      expect(result, isFalse);
      expect(logs, isEmpty);
    });

    test('logs missing user', () async {
      final logs = <String>[];
      final executor = CallReconnectExecutor(
        isDisposed: () => false,
        log: (message) => logs.add(message),
      );
      final result = await executor.reconnect(
        reason: 'test',
        reconnectUser: null,
        ensureRegistered: (_) async {},
      );
      expect(result, isFalse);
      expect(logs, ['[CALLS_CONN] reconnect skip reason=test missing_user']);
    });

    test('register success logs fired', () async {
      final logs = <String>[];
      final executor = CallReconnectExecutor(
        isDisposed: () => false,
        log: (message) => logs.add(message),
      );
      final user = const PbxSipUser(
        pbxSipUserId: 1,
        userId: 1,
        sipLogin: 'user',
        sipPassword: 'pass',
        dialplanId: 0,
        dongleId: null,
        pbxSipConnections: [],
      );
      final result = await executor.reconnect(
        reason: 'test',
        reconnectUser: user,
        ensureRegistered: (_) async {},
      );
      expect(result, isTrue);
      expect(logs, ['[CALLS_CONN] reconnect fired reason=test']);
    });

    test('register failure logs error', () async {
      final logs = <String>[];
      final executor = CallReconnectExecutor(
        isDisposed: () => false,
        log: (message) => logs.add(message),
      );
      final failure = Exception('boom');
      final user = const PbxSipUser(
        pbxSipUserId: 1,
        userId: 1,
        sipLogin: 'user',
        sipPassword: 'pass',
        dialplanId: 0,
        dongleId: null,
        pbxSipConnections: [],
      );
      final result = await executor.reconnect(
        reason: 'test',
        reconnectUser: user,
        ensureRegistered: (_) async => throw failure,
      );
      expect(result, isFalse);
      expect(logs, [
        '[CALLS_CONN] reconnect fired reason=test',
        '[CALLS_CONN] reconnect failed: Exception: boom',
      ]);
    });
  });
}
