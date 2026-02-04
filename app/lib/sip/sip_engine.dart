import 'dart:async';

import 'sip_models.dart';
export 'sip_models.dart';

abstract class SipEngine {
  Future<void> init();
  Future<void> register({
    required String uri,
    required String password,
    required String wsUrl,
    String? displayName,
  });
  Future<void> unregister();
  Future<String> makeCall(String number);
  Future<String> startCall(String destination);
  Future<void> hangup(String callId);
  Future<void> sendDtmf(String callId, String digits);
  Future<void> dispose();
  Stream<SipEvent> get events;
}

class SipUaEngine implements SipEngine {
  final StreamController<SipEvent> _eventController =
      StreamController<SipEvent>.broadcast();

  bool _initialized = false;
  SipRegistrationState _registrationState = SipRegistrationState.none;
  SipCallState _callState = SipCallState.none;
  String? _currentCallId;

  @override
  Stream<SipEvent> get events => _eventController.stream;

  void _emit(SipEvent event) {
    if (_eventController.isClosed) return;
    _eventController.add(event);
  }

  void _emitCall(SipEventType type, String message) {
    _callState = _callStateFromEvent(type);
    _emit(
      SipEvent(
        type: type,
        callId: _currentCallId ?? message,
        timestamp: DateTime.now(),
        message: message,
        callState: _callState,
      ),
    );
  }

  SipCallState _callStateFromEvent(SipEventType type) {
    switch (type) {
      case SipEventType.dialing:
        return SipCallState.dialing;
      case SipEventType.ringing:
        return SipCallState.ringing;
      case SipEventType.connected:
        return SipCallState.connected;
      case SipEventType.ended:
        return SipCallState.ended;
      case SipEventType.dtmf:
        return _callState == SipCallState.connected
            ? SipCallState.connected
            : SipCallState.dialing;
    }
  }

  @override
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    _registrationState = SipRegistrationState.none;
  }

  @override
  Future<void> register({
    required String uri,
    required String password,
    required String wsUrl,
    String? displayName,
  }) async {
    if (_registrationState == SipRegistrationState.registering ||
        _registrationState == SipRegistrationState.registered) {
      return;
    }

    _registrationState = SipRegistrationState.registering;
    await Future<void>.delayed(Duration.zero);
    _registrationState = SipRegistrationState.registered;
  }

  @override
  Future<void> unregister() async {
    if (_registrationState == SipRegistrationState.none ||
        _registrationState == SipRegistrationState.unregistered) {
      return;
    }
    _registrationState = SipRegistrationState.unregistering;
    await Future<void>.delayed(Duration.zero);
    _registrationState = SipRegistrationState.unregistered;
  }

  Future<String> _generateCallId(String destination) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final callId = '$destination#$timestamp';
    _currentCallId = callId;
    return callId;
  }

  @override
  Future<String> makeCall(String number) async {
    final callId = await _generateCallId(number);
    _emitCall(SipEventType.dialing, 'Набор $number');
    await Future<void>.delayed(Duration.zero);
    _emitCall(SipEventType.ringing, 'Звонок $number');
    return callId;
  }

  @override
  Future<String> startCall(String destination) async {
    return makeCall(destination);
  }

  @override
  Future<void> hangup(String callId) async {
    if (_currentCallId != callId) {
      return;
    }
    _emitCall(SipEventType.ended, 'Вызов завершён');
    await Future<void>.delayed(Duration.zero);
    _currentCallId = null;
    _callState = SipCallState.none;
  }

  @override
  Future<void> sendDtmf(String callId, String digits) async {
    if (_currentCallId != callId || digits.isEmpty) return;
    for (var i = 0; i < digits.length; i++) {
      final digit = digits[i];
      _emit(
        SipEvent(
          type: SipEventType.dtmf,
          callId: callId,
          message: 'DTMF $digit',
          digit: digit,
          timestamp: DateTime.now(),
          callState: _callState,
        ),
      );
      await Future<void>.delayed(Duration.zero);
    }
  }

  @override
  Future<void> dispose() async {
    await _eventController.close();
    _initialized = false;
  }
}

class FakeSipEngine implements SipEngine {
  final SipUaEngine _delegate = SipUaEngine();

  @override
  Stream<SipEvent> get events => _delegate.events;

  @override
  Future<void> dispose() => _delegate.dispose();

  @override
  Future<void> hangup(String callId) => _delegate.hangup(callId);

  @override
  Future<String> makeCall(String number) => _delegate.makeCall(number);

  @override
  Future<void> register({
    required String uri,
    required String password,
    required String wsUrl,
    String? displayName,
  }) =>
      _delegate.register(
        uri: uri,
        password: password,
        wsUrl: wsUrl,
        displayName: displayName,
      );

  @override
  Future<void> sendDtmf(String callId, String digits) =>
      _delegate.sendDtmf(callId, digits);

  @override
  Future<void> unregister() => _delegate.unregister();

  @override
  Future<void> init() => _delegate.init();

  @override
  Future<String> startCall(String destination) => _delegate.startCall(destination);
}

class PjsipSipEngine extends FakeSipEngine {}
