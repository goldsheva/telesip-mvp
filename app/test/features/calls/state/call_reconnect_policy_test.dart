import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/calls/state/call_reconnect_policy.dart';

void main() {
  group('CallReconnectPolicy.shouldScheduleReconnect', () {
    test('reports correct block reason', () {
      expect(
        CallReconnectPolicy.scheduleBlockReason(
          lastKnownOnline: true,
          hasActiveCall: false,
          authenticated: false,
        ),
        equals(CallReconnectScheduleBlockReason.notAuthenticated),
      );
      expect(
        CallReconnectPolicy.scheduleBlockReason(
          lastKnownOnline: false,
          hasActiveCall: false,
          authenticated: true,
        ),
        equals(CallReconnectScheduleBlockReason.offline),
      );
      expect(
        CallReconnectPolicy.scheduleBlockReason(
          lastKnownOnline: true,
          hasActiveCall: true,
          authenticated: true,
        ),
        equals(CallReconnectScheduleBlockReason.hasActiveCall),
      );
      expect(
        CallReconnectPolicy.scheduleBlockReason(
          lastKnownOnline: true,
          hasActiveCall: false,
          authenticated: true,
        ),
        isNull,
      );
    });
  });

  group('CallReconnectPolicy.shouldPerformReconnect', () {
    test('reports correct perform block reason', () {
      expect(
        CallReconnectPolicy.performBlockReason(
          lastKnownOnline: false,
          hasActiveCall: false,
          authenticated: true,
        ),
        equals(CallReconnectPerformBlockReason.offline),
      );
      expect(
        CallReconnectPolicy.performBlockReason(
          lastKnownOnline: true,
          hasActiveCall: true,
          authenticated: true,
        ),
        equals(CallReconnectPerformBlockReason.hasActiveCall),
      );
      expect(
        CallReconnectPolicy.performBlockReason(
          lastKnownOnline: true,
          hasActiveCall: false,
          authenticated: false,
        ),
        equals(CallReconnectPerformBlockReason.notAuthenticated),
      );
      expect(
        CallReconnectPolicy.performBlockReason(
          lastKnownOnline: true,
          hasActiveCall: false,
          authenticated: true,
        ),
        isNull,
      );
    });
  });
}
