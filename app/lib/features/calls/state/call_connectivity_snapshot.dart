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
    required bool registeredAt,
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
        'registeredAt=$registeredAt';
  }
}
