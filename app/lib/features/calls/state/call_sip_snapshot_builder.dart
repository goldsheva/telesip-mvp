import 'package:app/core/storage/sip_auth_storage.dart';
import 'package:app/features/sip_users/models/pbx_sip_connection.dart';

enum CallSipSnapshotBuildFailure {
  unsupportedTransport,
  missingWsEndpoint,
  invalidUriHost,
}

class CallSipSnapshotBuildResult {
  const CallSipSnapshotBuildResult({this.snapshot, this.failure});

  final SipAuthSnapshot? snapshot;
  final CallSipSnapshotBuildFailure? failure;
}

CallSipSnapshotBuildResult buildSipSnapshot({
  required Iterable<PbxSipConnection> connections,
  required String sipLogin,
  required String sipPassword,
  required String? defaultWsUrl,
  required bool treatEmptyDefaultAsMissing,
  required void Function(String message) setError,
}) {
  final wsConnections = connections
      .where((c) => c.pbxSipProtocol.toLowerCase().contains('ws'))
      .toList();
  late final String wsUrl;
  String uriHost = '';

  if (wsConnections.isNotEmpty) {
    final connection = wsConnections.first;
    final protocol = connection.pbxSipProtocol.toLowerCase();
    final scheme = protocol.contains('wss')
        ? 'wss'
        : protocol.contains('ws')
        ? 'ws'
        : null;
    if (scheme == null) {
      setError('Only WS/WSS transports are supported');
      return const CallSipSnapshotBuildResult(
        failure: CallSipSnapshotBuildFailure.unsupportedTransport,
      );
    }
    wsUrl = '$scheme://${connection.pbxSipUrl}:${connection.pbxSipPort}/';
    uriHost = Uri.tryParse(wsUrl)?.host ?? connection.pbxSipUrl;
  } else {
    if (defaultWsUrl == null ||
        (treatEmptyDefaultAsMissing && defaultWsUrl.isEmpty)) {
      setError(
        'PBX does not offer WS/WSS transport. Sip_ua requires SIP over WebSocket. '
        'Expected WSS (e.g., wss://pbx.teleleo.com:7443/).',
      );
      return const CallSipSnapshotBuildResult(
        failure: CallSipSnapshotBuildFailure.missingWsEndpoint,
      );
    }
    wsUrl = defaultWsUrl;
    uriHost = Uri.tryParse(wsUrl)?.host ?? '';
  }

  if (uriHost.isEmpty) {
    setError('Unable to determine SIP domain');
    return const CallSipSnapshotBuildResult(
      failure: CallSipSnapshotBuildFailure.invalidUriHost,
    );
  }

  final uri = 'sip:$sipLogin@$uriHost';
  return CallSipSnapshotBuildResult(
    snapshot: SipAuthSnapshot(
      uri: uri,
      password: sipPassword,
      wsUrl: wsUrl,
      displayName: sipLogin,
      timestamp: DateTime.now(),
    ),
  );
}

String incomingHintFailureMessage(CallSipSnapshotBuildFailure failure) {
  switch (failure) {
    case CallSipSnapshotBuildFailure.unsupportedTransport:
      return 'unsupported SIP transport for incoming user';
    case CallSipSnapshotBuildFailure.missingWsEndpoint:
      return 'no WS endpoint configured for incoming user';
    case CallSipSnapshotBuildFailure.invalidUriHost:
      return 'invalid WS URL for incoming user';
  }
}
