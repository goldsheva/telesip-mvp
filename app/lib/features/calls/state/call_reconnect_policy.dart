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
