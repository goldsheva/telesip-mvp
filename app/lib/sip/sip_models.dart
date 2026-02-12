enum SipRegistrationState {
  none,
  registering,
  registered,
  failed,
  unregistering,
  unregistered,
}

enum SipCallState { none, dialing, ringing, connected, ended, failed }

enum SipEventType {
  dialing,
  ringing,
  connected,
  ended,
  dtmf,
  registration,
  error,
}

class SipEvent {
  final SipEventType type;
  final String? callId;
  final DateTime timestamp;
  final String? message;
  final String? digit;
  final SipRegistrationState? registrationState;
  final SipCallState? callState;
  final int? statusCode;
  final String? reasonPhrase;
  final String? sipCause;

  SipEvent({
    required this.type,
    this.callId,
    DateTime? timestamp,
    this.message,
    this.digit,
    this.registrationState,
    this.callState,
    this.statusCode,
    this.reasonPhrase,
    this.sipCause,
  }) : timestamp = timestamp ?? DateTime.now();

  SipEvent copyWith({
    SipEventType? type,
    String? callId,
    DateTime? timestamp,
    String? message,
    String? digit,
    SipRegistrationState? registrationState,
    SipCallState? callState,
    int? statusCode,
    String? reasonPhrase,
    String? sipCause,
  }) {
    return SipEvent(
      type: type ?? this.type,
      callId: callId ?? this.callId,
      timestamp: timestamp ?? this.timestamp,
      message: message ?? this.message,
      digit: digit ?? this.digit,
      registrationState: registrationState ?? this.registrationState,
      callState: callState ?? this.callState,
      statusCode: statusCode ?? this.statusCode,
      reasonPhrase: reasonPhrase ?? this.reasonPhrase,
      sipCause: sipCause ?? this.sipCause,
    );
  }
}
