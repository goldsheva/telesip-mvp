import 'package:app/features/calls/state/call_connectivity_snapshot.dart';

class CallConnectivityDebugDumper {
  const CallConnectivityDebugDumper();

  void dumpShort({
    required bool disposed,
    required bool kDebugModeEnabled,
    required String tag,
    required String authStatusName,
    required bool online,
    required bool bootstrapScheduled,
    required bool bootstrapDone,
    required bool bootstrapInFlight,
    required DateTime? lastNetworkActivityAt,
    required int backoffIndex,
    required String? activeCallId,
    required Object? activeCallStatus,
    required DateTime? lastSipRegisteredAt,
    required void Function(String msg) log,
  }) {
    if (disposed || !kDebugModeEnabled) return;
    final lastNetAge = _formatLastNetAge(lastNetworkActivityAt);
    final statusString = (activeCallStatus ?? '<none>').toString();
    final activeCallIdString = activeCallId ?? '<none>';
    log(
      CallConnectivitySnapshot.formatShort(
        tag: tag,
        authStatus: authStatusName,
        online: online,
        bootstrapScheduled: bootstrapScheduled,
        bootstrapDone: bootstrapDone,
        bootstrapInFlight: bootstrapInFlight,
        lastNetAge: lastNetAge,
        backoffIndex: backoffIndex,
        activeCallId: activeCallIdString,
        activeCallStatus: statusString,
        registeredAt: lastSipRegisteredAt != null,
      ),
    );
  }

  void dump({
    required bool disposed,
    required bool kDebugModeEnabled,
    required String tag,
    required String authStatusName,
    required bool online,
    required bool bootstrapScheduled,
    required bool bootstrapDone,
    required bool bootstrapInFlight,
    required bool engineRegistered,
    required bool stateRegistered,
    required String lastRegistrationStateName,
    required DateTime? lastNetworkActivityAt,
    required bool healthTimerActive,
    required bool reconnectTimerActive,
    required bool reconnectInFlight,
    required int backoffIndex,
    required String activeCallId,
    required Object? activeCallStatus,
    required void Function(String msg) log,
  }) {
    if (disposed || !kDebugModeEnabled) return;
    final lastNetAge = _formatLastNetAge(lastNetworkActivityAt);
    final statusString = (activeCallStatus ?? '<none>').toString();
    log(
      CallConnectivitySnapshot.format(
        tag: tag,
        authStatus: authStatusName,
        online: online,
        bootstrapScheduled: bootstrapScheduled,
        bootstrapDone: bootstrapDone,
        bootstrapInFlight: bootstrapInFlight,
        registered: engineRegistered,
        stateRegistered: stateRegistered,
        lastRegistrationState: lastRegistrationStateName,
        lastNetAge: lastNetAge,
        healthTimerActive: healthTimerActive,
        reconnectTimerActive: reconnectTimerActive,
        reconnectInFlight: reconnectInFlight,
        backoffIndex: backoffIndex,
        activeCallId: activeCallId,
        activeCallStatus: statusString,
      ),
    );
  }

  String _formatLastNetAge(DateTime? lastNetworkActivityAt) {
    if (lastNetworkActivityAt == null) return '<none>';
    final ageSeconds = DateTime.now()
        .difference(lastNetworkActivityAt)
        .inSeconds;
    return '${ageSeconds}s';
  }
}
