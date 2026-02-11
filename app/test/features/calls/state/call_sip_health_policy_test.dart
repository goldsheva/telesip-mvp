import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/calls/state/call_sip_health_policy.dart';

void main() {
  group('CallSipHealthPolicy', () {
    test('stop when offline or unauthenticated or healthy', () {
      expect(
        CallSipHealthPolicy.shouldStopWatchdog(
          online: false,
          authenticated: true,
          sipHealthyNow: false,
        ),
        isTrue,
      );
      expect(
        CallSipHealthPolicy.shouldStopWatchdog(
          online: true,
          authenticated: false,
          sipHealthyNow: false,
        ),
        isTrue,
      );
      expect(
        CallSipHealthPolicy.shouldStopWatchdog(
          online: true,
          authenticated: true,
          sipHealthyNow: true,
        ),
        isTrue,
      );
      expect(
        CallSipHealthPolicy.shouldStopWatchdog(
          online: true,
          authenticated: true,
          sipHealthyNow: false,
        ),
        isFalse,
      );
    });

    test('start only when online, authenticated, not running, not healthy', () {
      expect(
        CallSipHealthPolicy.shouldStartWatchdog(
          online: true,
          authenticated: true,
          watchdogRunning: false,
          sipHealthyNow: false,
        ),
        isTrue,
      );
      expect(
        CallSipHealthPolicy.shouldStartWatchdog(
          online: false,
          authenticated: true,
          watchdogRunning: false,
          sipHealthyNow: false,
        ),
        isFalse,
      );
      expect(
        CallSipHealthPolicy.shouldStartWatchdog(
          online: true,
          authenticated: false,
          watchdogRunning: false,
          sipHealthyNow: false,
        ),
        isFalse,
      );
      expect(
        CallSipHealthPolicy.shouldStartWatchdog(
          online: true,
          authenticated: true,
          watchdogRunning: true,
          sipHealthyNow: false,
        ),
        isFalse,
      );
      expect(
        CallSipHealthPolicy.shouldStartWatchdog(
          online: true,
          authenticated: true,
          watchdogRunning: false,
          sipHealthyNow: true,
        ),
        isFalse,
      );
    });
  });
}
