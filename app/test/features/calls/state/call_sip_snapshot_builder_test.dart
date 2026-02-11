import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/calls/state/call_sip_snapshot_builder.dart';
import 'package:app/features/sip_users/models/pbx_sip_connection.dart';

void main() {
  group('buildSipSnapshot', () {
    test('builds snapshot from first WS connection', () {
      const connections = [
        PbxSipConnection(
          pbxSipUrl: 'pbx.teleleo.com',
          pbxSipPort: 7443,
          pbxSipProtocol: 'WSS',
        ),
        PbxSipConnection(
          pbxSipUrl: 'ignored.example.com',
          pbxSipPort: 7443,
          pbxSipProtocol: 'ws',
        ),
      ];
      final errors = <String>[];
      final result = buildSipSnapshot(
        connections: connections,
        sipLogin: 'user',
        sipPassword: 'secret',
        defaultWsUrl: null,
        allowEmptyDefaultWsUrl: false,
        setError: errors.add,
      );

      expect(result.snapshot, isNotNull);
      expect(result.snapshot!.wsUrl, 'wss://pbx.teleleo.com:7443/');
      expect(result.snapshot!.uri, 'sip:user@pbx.teleleo.com');
      expect(result.snapshot!.displayName, 'user');
      expect(errors, isEmpty);
    });

    test('falls back to default WS URL when no connections', () {
      const connections = <PbxSipConnection>[];
      final errors = <String>[];
      final result = buildSipSnapshot(
        connections: connections,
        sipLogin: 'fallback',
        sipPassword: 'secret',
        defaultWsUrl: 'wss://fallback.example:7443/',
        allowEmptyDefaultWsUrl: true,
        setError: errors.add,
      );

      expect(result.snapshot, isNotNull);
      expect(result.snapshot!.wsUrl, 'wss://fallback.example:7443/');
      expect(result.snapshot!.uri, 'sip:fallback@fallback.example');
      expect(errors, isEmpty);
    });

    test('reports missing WS endpoint when default missing', () {
      const connections = <PbxSipConnection>[];
      final errors = <String>[];
      final result = buildSipSnapshot(
        connections: connections,
        sipLogin: 'user',
        sipPassword: 'secret',
        defaultWsUrl: null,
        allowEmptyDefaultWsUrl: false,
        setError: errors.add,
      );

      expect(result.snapshot, isNull);
      expect(result.failure, CallSipSnapshotBuildFailure.missingWsEndpoint);
      expect(errors, [
        'PBX does not offer WS/WSS transport. Sip_ua requires SIP over WebSocket. '
            'Expected WSS (e.g., wss://pbx.teleleo.com:7443/).',
      ]);
    });

    test('reports invalid URI host when host cannot be determined', () {
      const connections = [
        PbxSipConnection(
          pbxSipUrl: '',
          pbxSipPort: 7443,
          pbxSipProtocol: 'WSS',
        ),
      ];
      final errors = <String>[];
      final result = buildSipSnapshot(
        connections: connections,
        sipLogin: 'user',
        sipPassword: 'secret',
        defaultWsUrl: null,
        allowEmptyDefaultWsUrl: false,
        setError: errors.add,
      );

      expect(result.snapshot, isNull);
      expect(result.failure, CallSipSnapshotBuildFailure.invalidUriHost);
      expect(errors, ['Unable to determine SIP domain']);
    });
  });
}
