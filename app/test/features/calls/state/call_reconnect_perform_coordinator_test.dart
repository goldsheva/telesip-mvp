import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/calls/state/call_reconnect_log.dart';
import 'package:app/features/calls/state/call_reconnect_perform_coordinator.dart';
import 'package:app/features/calls/state/call_reconnect_policy.dart';

void main() {
  group('CallReconnectPerformCoordinator.decidePerform', () {
    final baseArgs = {
      'reason': 'reason',
      'authStatusName': 'auth',
      'activeCallId': '<call>',
      'disposed': false,
      'reconnectInFlight': false,
      'online': true,
      'hasActiveCall': false,
      'authenticated': true,
    };

    ReconnectPerformDecision callWithOverrides(Map<String, Object?> overrides) {
      return CallReconnectPerformCoordinator.decidePerform(
        reason: overrides['reason'] as String? ?? baseArgs['reason'] as String,
        authStatusName:
            overrides['authStatusName'] as String? ??
            baseArgs['authStatusName'] as String,
        activeCallId:
            overrides['activeCallId'] as String? ??
            baseArgs['activeCallId'] as String,
        disposed:
            overrides['disposed'] as bool? ?? baseArgs['disposed'] as bool,
        reconnectInFlight:
            overrides['reconnectInFlight'] as bool? ??
            baseArgs['reconnectInFlight'] as bool,
        online: overrides['online'] as bool? ?? baseArgs['online'] as bool,
        hasActiveCall:
            overrides['hasActiveCall'] as bool? ??
            baseArgs['hasActiveCall'] as bool,
        authenticated:
            overrides['authenticated'] as bool? ??
            baseArgs['authenticated'] as bool,
      );
    }

    test('skips when disposed', () {
      final decision = callWithOverrides({'disposed': true});
      expect(decision, isA<ReconnectPerformDecisionSkip>());
      final skip = decision as ReconnectPerformDecisionSkip;
      expect(skip.disposed, isTrue);
      expect(skip.message, isNull);
    });

    test('skips when reconnect in flight', () {
      final decision = callWithOverrides({'reconnectInFlight': true});
      expect(decision, isA<ReconnectPerformDecisionSkip>());
      final skip = decision as ReconnectPerformDecisionSkip;
      expect(skip.inFlight, isTrue);
      expect(skip.message, isNull);
    });

    test('skips for offline reason with log message', () {
      final decision = callWithOverrides({'online': false});
      expect(decision, isA<ReconnectPerformDecisionSkip>());
      final skip = decision as ReconnectPerformDecisionSkip;
      expect(skip.reason, CallReconnectPerformBlockReason.offline);
      expect(skip.message, CallReconnectLog.reconnectSkipOffline('reason'));
    });

    test('skips for active call reason with log message', () {
      final decision = callWithOverrides({'hasActiveCall': true});
      expect(decision, isA<ReconnectPerformDecisionSkip>());
      final skip = decision as ReconnectPerformDecisionSkip;
      expect(skip.reason, CallReconnectPerformBlockReason.hasActiveCall);
      expect(
        skip.message,
        CallReconnectLog.reconnectSkipHasActiveCall('reason', '<call>'),
      );
    });

    test('skips for authentication reason with log message', () {
      final decision = callWithOverrides({'authenticated': false});
      expect(decision, isA<ReconnectPerformDecisionSkip>());
      final skip = decision as ReconnectPerformDecisionSkip;
      expect(skip.reason, CallReconnectPerformBlockReason.notAuthenticated);
      expect(
        skip.message,
        CallReconnectLog.reconnectSkipNotAuthenticated('reason', 'auth'),
      );
    });

    test('allows when no blockers', () {
      final decision = callWithOverrides({});
      expect(decision, isA<ReconnectPerformDecisionAllow>());
    });
  });
}
