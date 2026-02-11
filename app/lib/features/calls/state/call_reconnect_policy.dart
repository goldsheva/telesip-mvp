enum CallReconnectScheduleBlockReason {
  notAuthenticated,
  offline,
  hasActiveCall,
}

enum CallReconnectPerformBlockReason {
  disposed,
  inFlight,
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
    required bool disposed,
    required bool reconnectInFlight,
    required bool lastKnownOnline,
    required bool hasActiveCall,
    required bool authenticated,
  }) {
    if (disposed) return CallReconnectPerformBlockReason.disposed;
    if (reconnectInFlight) return CallReconnectPerformBlockReason.inFlight;
    if (!lastKnownOnline) return CallReconnectPerformBlockReason.offline;
    if (hasActiveCall) return CallReconnectPerformBlockReason.hasActiveCall;
    if (!authenticated) return CallReconnectPerformBlockReason.notAuthenticated;
    return null;
  }
}
