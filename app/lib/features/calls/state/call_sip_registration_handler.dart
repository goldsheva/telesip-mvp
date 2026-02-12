import 'package:flutter/foundation.dart';

import 'package:app/features/calls/state/call_models.dart';
import 'package:app/sip/sip_engine.dart';

class CallSipRegistrationHandler {
  CallSipRegistrationHandler({
    required this.setLastNetworkActivityAt,
    required this.setLastSipRegisteredAt,
    required this.resetReconnectBackoff,
    required this.hasReconnectTimer,
    required this.isReconnectInFlight,
    required this.setReconnectInFlight,
    required this.cancelReconnect,
    required this.stopHealthWatchdog,
    required this.setLastRegistrationState,
    required this.setIsRegistered,
    required this.getIsRegistered,
    required this.setRegisteredUserId,
    required this.getLastKnownUserId,
    required this.cancelRegistrationErrorTimer,
    required this.setPendingRegistrationError,
    required this.clearErrorSafe,
    required this.handleRegistrationFailure,
    required this.scheduleReconnect,
    required this.maybeStartHealthWatchdog,
    required this.getState,
    required this.commitState,
  });

  final void Function(DateTime) setLastNetworkActivityAt;
  final void Function(DateTime) setLastSipRegisteredAt;
  final void Function() resetReconnectBackoff;
  final bool Function() hasReconnectTimer;
  final bool Function() isReconnectInFlight;
  final void Function(bool) setReconnectInFlight;
  final void Function() cancelReconnect;
  final void Function() stopHealthWatchdog;
  final void Function(SipRegistrationState) setLastRegistrationState;
  final void Function(bool) setIsRegistered;
  final bool Function() getIsRegistered;
  final void Function(int?) setRegisteredUserId;
  final int? Function() getLastKnownUserId;
  final void Function() cancelRegistrationErrorTimer;
  final void Function(String?) setPendingRegistrationError;
  final void Function() clearErrorSafe;
  final void Function(String) handleRegistrationFailure;
  final void Function(String) scheduleReconnect;
  final void Function() maybeStartHealthWatchdog;
  final CallState Function() getState;
  final void Function(CallState) commitState;

  bool handle(SipEvent event, DateTime now) {
    if (event.type != SipEventType.registration) {
      return false;
    }
    final registrationState = event.registrationState;
    if (registrationState != null) {
      setLastNetworkActivityAt(now);
      if (registrationState == SipRegistrationState.registered) {
        setLastSipRegisteredAt(now);
        resetReconnectBackoff();
        if (hasReconnectTimer() || isReconnectInFlight()) {
          debugPrint(
            '[CALLS_CONN] reconnect cleared due to registration success',
          );
          cancelReconnect();
          setReconnectInFlight(false);
        }
        stopHealthWatchdog();
      }
      setLastRegistrationState(registrationState);
    }
    if (registrationState == SipRegistrationState.registered) {
      setIsRegistered(true);
      setRegisteredUserId(getLastKnownUserId());
      cancelRegistrationErrorTimer();
      setPendingRegistrationError(null);
      clearErrorSafe();
    } else if (registrationState == SipRegistrationState.failed) {
      setIsRegistered(false);
      handleRegistrationFailure(event.message ?? 'SIP registration failed');
      final stateName = registrationState?.name ?? 'unknown';
      scheduleReconnect('registration-$stateName');
      maybeStartHealthWatchdog();
    } else if (registrationState == SipRegistrationState.unregistered ||
        registrationState == SipRegistrationState.none) {
      setIsRegistered(false);
      setRegisteredUserId(null);
      if (registrationState == SipRegistrationState.unregistered) {
        final stateName = registrationState?.name ?? 'unknown';
        scheduleReconnect('registration-$stateName');
        maybeStartHealthWatchdog();
      }
    }
    commitState(getState().copyWith(isRegistered: getIsRegistered()));
    return true;
  }
}
