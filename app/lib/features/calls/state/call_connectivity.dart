import 'dart:async';

import 'package:app/services/network_connectivity_service.dart';

// -----------------------------------------------------------------------------
// Connectivity listener
// -----------------------------------------------------------------------------

class CallConnectivityListener {
  CallConnectivityListener({
    required this.connectivityService,
    required this.isDisposed,
    required this.onOnlineChanged,
    required this.onInitialOnlineResolved,
    required this.logSnapshot,
  });

  final NetworkConnectivityService connectivityService;
  final bool Function() isDisposed;
  final void Function(bool online) onOnlineChanged;
  final void Function(bool online) onInitialOnlineResolved;
  final void Function(String tag) logSnapshot;

  StreamSubscription<bool>? _subscription;
  bool _started = false;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    _subscription = connectivityService.onOnlineChanged.listen((online) {
      if (isDisposed()) return;
      onOnlineChanged(online);
    });
    final online = await connectivityService.isOnline();
    if (isDisposed()) return;
    onInitialOnlineResolved(online);
    logSnapshot('connectivity-init');
  }

  void dispose() {
    _subscription?.cancel();
    _subscription = null;
  }
}

// -----------------------------------------------------------------------------
// Connectivity snapshot formatter
// -----------------------------------------------------------------------------

class CallConnectivitySnapshot {
  static String format({
    required String tag,
    required String authStatus,
    required bool online,
    required bool bootstrapScheduled,
    required bool bootstrapDone,
    required bool bootstrapInFlight,
    required String lastRegistrationState,
    required String lastNetAge,
    required bool healthTimerActive,
    required bool reconnectTimerActive,
    required bool reconnectInFlight,
    required int backoffIndex,
    required String activeCallId,
    required String activeCallStatus,
    required bool registered,
    required bool stateRegistered,
  }) {
    return '[CALLS_CONN] $tag '
        'authStatus=$authStatus '
        'online=$online '
        'scheduled=$bootstrapScheduled '
        'done=$bootstrapDone '
        'inFlight=$bootstrapInFlight '
        'registered=$registered '
        'stateRegistered=$stateRegistered '
        'lastRegistrationState=$lastRegistrationState '
        'lastNetAge=$lastNetAge '
        'healthTimer=$healthTimerActive '
        'reconnectTimer=$reconnectTimerActive '
        'reconnectInFlight=$reconnectInFlight '
        'backoffIndex=$backoffIndex '
        'active=$activeCallId '
        'status=$activeCallStatus';
  }

  static String formatShort({
    required String tag,
    required String authStatus,
    required bool online,
    required bool bootstrapScheduled,
    required bool bootstrapDone,
    required bool bootstrapInFlight,
    required String lastNetAge,
    required int backoffIndex,
    required String activeCallId,
    required String activeCallStatus,
    required bool hasSipRegisteredAt,
  }) {
    return '[CALLS_CONN] $tag '
        'authStatus=$authStatus '
        'online=$online '
        'scheduled=$bootstrapScheduled '
        'done=$bootstrapDone '
        'inFlight=$bootstrapInFlight '
        'active=$activeCallId '
        'status=$activeCallStatus '
        'lastNetAge=$lastNetAge '
        'backoffIndex=$backoffIndex '
        'registeredAt=$hasSipRegisteredAt';
  }
}

// -----------------------------------------------------------------------------
// Connectivity debug dumper
// -----------------------------------------------------------------------------

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
        hasSipRegisteredAt: lastSipRegisteredAt != null,
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
