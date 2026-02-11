import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:app/features/auth/state/auth_notifier.dart';
import 'package:app/features/auth/state/auth_state.dart';
import 'package:app/features/calls/state/call_reconnect_decision.dart';

String activeCallIdForLogs(String? activeCallId) => activeCallId ?? '<none>';

AuthStatus currentAuthStatus(Ref ref) =>
    ref.read(authNotifierProvider).value?.status ?? AuthStatus.unknown;

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
