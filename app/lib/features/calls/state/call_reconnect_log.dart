class CallReconnectLog {
  CallReconnectLog._();

  static String scheduleSkipNotAuthenticated(
    String reason,
    String authStatus,
  ) =>
      '[CALLS_CONN] scheduleReconnect skip reason=$reason authStatus=$authStatus';

  static String scheduleSkipOffline(String reason) =>
      '[CALLS_CONN] scheduleReconnect skip reason=$reason online=false';

  static String scheduleSkipHasActiveCall(String reason, String activeCallId) =>
      '[CALLS_CONN] scheduleReconnect skip reason=$reason activeCallId=$activeCallId';

  static String scheduleSkipInFlight(String reason) =>
      '[CALLS_CONN] scheduleReconnect skip reason=$reason inFlight=true';

  static String scheduleScheduled({
    required String reason,
    required int attemptNumber,
    required int delayMs,
    required bool online,
    required String authStatus,
    required bool registered,
    required String lastNetAge,
    required int backoffIndex,
  }) =>
      '[CALLS_CONN] scheduleReconnect reason=$reason attempt=$attemptNumber '
      'delayMs=$delayMs online=$online authStatus=$authStatus registered=$registered '
      'lastNetAge=$lastNetAge backoffIndex=$backoffIndex';

  static String reconnectSkipOffline(String reason) =>
      '[CALLS_CONN] reconnect skip reason=$reason online=false';

  static String reconnectSkipHasActiveCall(
    String reason,
    String activeCallId,
  ) => '[CALLS_CONN] reconnect skip reason=$reason activeCallId=$activeCallId';

  static String reconnectSkipNotAuthenticated(
    String reason,
    String authStatus,
  ) => '[CALLS_CONN] reconnect skip reason=$reason authStatus=$authStatus';

  static String reconnectSkipMissingUser(String reason) =>
      '[CALLS_CONN] reconnect skip reason=$reason missing_user';

  static String reconnectFired(String reason) =>
      '[CALLS_CONN] reconnect fired reason=$reason';

  static String reconnectFailed(Object error) =>
      '[CALLS_CONN] reconnect failed: $error';
}
