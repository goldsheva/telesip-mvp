// -----------------------------------------------------------------------------
// Reconnect scheduler API
// -----------------------------------------------------------------------------

abstract class CallReconnectSchedulerApi {
  void cancel();
  Duration get currentDelay;
  int get currentAttemptNumber;
  int get backoffIndex;
  void schedule({required String reason, required void Function() onFire});
}

// -----------------------------------------------------------------------------
// Reconnect log helpers
// -----------------------------------------------------------------------------

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

// -----------------------------------------------------------------------------
// Reconnect policy
// -----------------------------------------------------------------------------

enum CallReconnectScheduleBlockReason {
  notAuthenticated,
  offline,
  hasActiveCall,
}

enum CallReconnectPerformBlockReason {
  offline,
  hasActiveCall,
  notAuthenticated,
}

class CallReconnectPolicy {
  CallReconnectPolicy._();

  static CallReconnectScheduleBlockReason? scheduleBlockReason({
    required bool lastKnownOnline,
    required bool hasActiveCall,
    required bool authenticated,
  }) {
    if (!authenticated) {
      return CallReconnectScheduleBlockReason.notAuthenticated;
    }
    if (!lastKnownOnline) return CallReconnectScheduleBlockReason.offline;
    if (hasActiveCall) return CallReconnectScheduleBlockReason.hasActiveCall;
    return null;
  }

  static CallReconnectPerformBlockReason? performBlockReason({
    required bool lastKnownOnline,
    required bool hasActiveCall,
    required bool authenticated,
  }) {
    if (!lastKnownOnline) return CallReconnectPerformBlockReason.offline;
    if (hasActiveCall) return CallReconnectPerformBlockReason.hasActiveCall;
    if (!authenticated) return CallReconnectPerformBlockReason.notAuthenticated;
    return null;
  }
}

// -----------------------------------------------------------------------------
// Reconnect decision types
// -----------------------------------------------------------------------------

abstract class ReconnectDecision {
  const ReconnectDecision._();
}

class ReconnectDecisionSkip extends ReconnectDecision {
  const ReconnectDecisionSkip({
    this.disposed = false,
    this.inFlight = false,
    this.message,
  }) : super._();

  final bool disposed;
  final bool inFlight;
  final String? message;
}

class ReconnectDecisionAllow extends ReconnectDecision {
  const ReconnectDecisionAllow() : super._();
}

// -----------------------------------------------------------------------------
// Reconnect helper utilities
// -----------------------------------------------------------------------------

String activeCallIdForLogs(String? activeCallId) => activeCallId ?? '<none>';
bool handleReconnectDecision({
  required ReconnectDecision decision,
  required bool treatInFlightAsSilent,
  required void Function(String message) log,
}) {
  if (decision is! ReconnectDecisionSkip) return false;
  if (decision.disposed) return true;
  if (decision.inFlight) {
    if (treatInFlightAsSilent) return true;
    final message = decision.message;
    if (message != null) {
      log(message);
    }
    return true;
  }
  final message = decision.message;
  if (message != null) {
    log(message);
  }
  return true;
}
