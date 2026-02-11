class CallSipHealthPolicy {
  CallSipHealthPolicy._();

  static bool shouldStopWatchdog({
    required bool online,
    required bool authenticated,
    required bool sipHealthyNow,
  }) {
    if (!online || !authenticated) return true;
    if (sipHealthyNow) return true;
    return false;
  }

  static bool shouldStartWatchdog({
    required bool online,
    required bool authenticated,
    required bool watchdogRunning,
    required bool sipHealthyNow,
  }) {
    if (!online || !authenticated) return false;
    if (watchdogRunning) return false;
    if (sipHealthyNow) return false;
    return true;
  }
}
