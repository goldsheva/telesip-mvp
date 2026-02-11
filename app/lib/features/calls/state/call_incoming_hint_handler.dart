import 'package:app/config/env_config.dart';
import 'package:app/core/storage/fcm_storage.dart';
import 'package:app/core/storage/general_sip_credentials_storage.dart';
import 'package:app/core/storage/sip_auth_storage.dart';
import 'package:app/features/sip_users/models/pbx_sip_user.dart';

class CallIncomingHintHandler {
  CallIncomingHintHandler({
    required this.isDisposed,
    required this.ensureStoredIncomingCredentialsLoaded,
    required this.registerWithSnapshot,
    required this.getIncomingUser,
    required this.setIncomingUser,
    required this.getStoredIncomingCredentials,
    required this.incomingUserFromStoredCredentials,
    required this.readStoredSnapshot,
    required this.startHintForegroundGuard,
    required this.releaseHintForegroundGuard,
    required this.isBusy,
    required this.log,
  });

  static const Duration _incomingHintExpiry = Duration(seconds: 60);
  static const Duration _incomingHintRetryTtl = Duration(seconds: 30);

  final bool Function() isDisposed;
  final Future<void> Function() ensureStoredIncomingCredentialsLoaded;
  final Future<bool> Function(SipAuthSnapshot snapshot) registerWithSnapshot;
  final PbxSipUser? Function() getIncomingUser;
  final void Function(PbxSipUser user) setIncomingUser;
  final GeneralSipCredentials? Function() getStoredIncomingCredentials;
  final PbxSipUser Function(GeneralSipCredentials creds)
  incomingUserFromStoredCredentials;
  final Future<SipAuthSnapshot?> Function() readStoredSnapshot;
  final void Function() startHintForegroundGuard;
  final void Function({required bool registered, bool sync})
  releaseHintForegroundGuard;
  final bool Function() isBusy;
  final void Function(String message) log;

  bool _isHandlingHint = false;
  DateTime? _lastHandledHintTimestamp;
  DateTime? _lastHintAttemptAt;

  Future<void> handleIncomingCallHintIfAny() async {
    if (isDisposed()) return;
    await ensureStoredIncomingCredentialsLoaded();
    if (isDisposed()) return;
    if (_isHandlingHint) return;
    _isHandlingHint = true;
    try {
      final raw = await FcmStorage.readPendingIncomingHint();
      if (isDisposed()) return;
      if (raw == null) return;

      final payload = raw['payload'] as Map<String, dynamic>?;
      final timestampRaw = raw['timestamp'] as String?;
      final timestamp = DateTime.tryParse(timestampRaw ?? '');
      final callUuid = payload?['call_uuid']?.toString() ?? '<none>';

      if (payload == null || timestamp == null) {
        log('[INCOMING] invalid pending hint (call_uuid=$callUuid), clearing');
        await FcmStorage.clearPendingIncomingHint();
        if (isDisposed()) return;
        return;
      }

      final now = DateTime.now();
      if (now.difference(timestamp) > _incomingHintExpiry) {
        log(
          '[INCOMING] pending hint expired after ${now.difference(timestamp).inSeconds}s (call_uuid=$callUuid)',
        );
        await FcmStorage.clearPendingIncomingHint();
        if (isDisposed()) return;
        return;
      }

      if (_lastHandledHintTimestamp != null &&
          _lastHandledHintTimestamp!.isAtSameMomentAs(timestamp)) {
        return;
      }

      if (_lastHintAttemptAt != null &&
          now.difference(_lastHintAttemptAt!) < _incomingHintRetryTtl) {
        final remaining =
            _incomingHintRetryTtl - now.difference(_lastHintAttemptAt!);
        log(
          '[INCOMING] hint retry suppressed for ${remaining.inSeconds}s (call_uuid=$callUuid)',
        );
        return;
      }

      if (isBusy()) {
        log(
          '[INCOMING] busy when handling hint (call_uuid=$callUuid), will retry later',
        );
        return;
      }

      _lastHintAttemptAt = now;
      final storedCreds = getStoredIncomingCredentials();
      final candidate =
          getIncomingUser() ??
          (storedCreds != null
              ? incomingUserFromStoredCredentials(storedCreds)
              : null);
      late final SipAuthSnapshot snapshot;
      if (candidate != null) {
        setIncomingUser(candidate);
        final wsConnections = candidate.pbxSipConnections
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
            log(
              '[INCOMING] unsupported SIP transport for incoming user, skipping hint (call_uuid=$callUuid)',
            );
            return;
          }
          wsUrl = '$scheme://${connection.pbxSipUrl}:${connection.pbxSipPort}/';
          uriHost = Uri.tryParse(wsUrl)?.host ?? connection.pbxSipUrl;
        } else {
          final defaultWs = EnvConfig.sipWebSocketUrl;
          if (defaultWs == null || defaultWs.isEmpty) {
            log(
              '[INCOMING] no WS endpoint configured for incoming user, skipping hint (call_uuid=$callUuid)',
            );
            return;
          }
          wsUrl = defaultWs;
          uriHost = Uri.tryParse(wsUrl)?.host ?? '';
        }
        if (uriHost.isEmpty) {
          log(
            '[INCOMING] invalid WS URL for incoming user, skipping hint (call_uuid=$callUuid)',
          );
          return;
        }
        snapshot = SipAuthSnapshot(
          uri: 'sip:${candidate.sipLogin}@$uriHost',
          password: candidate.sipPassword,
          wsUrl: wsUrl,
          displayName: candidate.sipLogin,
          timestamp: DateTime.now(),
        );
        log(
          '[INCOMING] registering SIP from stored incoming user (call_uuid=$callUuid)',
        );
      } else {
        final storedSnapshot = await readStoredSnapshot();
        if (isDisposed()) return;
        if (storedSnapshot == null) {
          log(
            '[INCOMING] no stored SIP credentials to register (call_uuid=$callUuid)',
          );
          return;
        }
        snapshot = storedSnapshot;
        log('[INCOMING] registering SIP from hint (call_uuid=$callUuid)');
      }
      var registered = false;
      try {
        startHintForegroundGuard();
        registered = await registerWithSnapshot(snapshot);
        if (isDisposed()) return;
        if (registered) {
          _lastHandledHintTimestamp = timestamp;
          await FcmStorage.clearPendingIncomingHint();
          if (isDisposed()) return;
          log(
            '[INCOMING] pending hint handled and cleared (call_uuid=$callUuid)',
          );
        } else {
          if (isDisposed()) return;
          log(
            '[INCOMING] hint handling failed, retry allowed after ${_incomingHintRetryTtl.inSeconds}s (call_uuid=$callUuid)',
          );
        }
      } finally {
        releaseHintForegroundGuard(registered: registered, sync: !registered);
      }
    } finally {
      _isHandlingHint = false;
    }
  }
}
