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

  void _emitRegistration(
    SipRegistrationState state, {
    String? message,
  }) {
    _emit(
      SipEvent(
        type: SipEventType.registration,
        registrationState: state,
        message: message,
      ),
    );
  }

  void _emitCall(SipEventType type, {String? message}) {
    if (_currentCallId == null) return;
    _callState = _callStateFromEvent(type);
    _emit(
      SipEvent(
        type: type,
        callId: _currentCallId,
        message: message,
        callState: _callState,
      ),
    );
  }

  void _emitError(String message, {String? callId}) {
    _emit(
      SipEvent(
        type: SipEventType.error,
        callId: callId,
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
      case SipEventType.registration:
      case SipEventType.error:
        return _callState;
    }
  }

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    await init();
  }

  Future<String> _generateCallId(String destination) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final callId = '$destination#$timestamp';
    _currentCallId = callId;
    return callId;
  }

  @override
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    _registrationState = SipRegistrationState.none;
    _callState = SipCallState.none;
  }

  @override
  Future<void> register({
    required String uri,
    required String password,
    required String wsUrl,
    String? displayName,
  }) async {
    await _ensureInitialized();
    if (_registrationState == SipRegistrationState.registering ||
        _registrationState == SipRegistrationState.registered) {
      return;
    }

    _registrationState = SipRegistrationState.registering;
    final registrationMessage = displayName != null && displayName.isNotEmpty
        ? 'Регистрируемся как $displayName'
        : 'Регистрируемся...';
    _emitRegistration(
      SipRegistrationState.registering,
      message: registrationMessage,
    );

    await Future<void>.delayed(const Duration(milliseconds: 10));

    final registrationSuccess =
        uri.isNotEmpty && password.isNotEmpty && wsUrl.isNotEmpty;
    if (registrationSuccess) {
      _registrationState = SipRegistrationState.registered;
      _emitRegistration(
        SipRegistrationState.registered,
        message: 'Регистрация завершена',
      );
      return;
    }

    _registrationState = SipRegistrationState.failed;
    _emitRegistration(
      SipRegistrationState.failed,
      message: 'Ошибка регистрации',
    );
    _emitError('Регистрация не удалась');
  }

  @override
  Future<void> unregister() async {
    if (_registrationState == SipRegistrationState.none ||
        _registrationState == SipRegistrationState.unregistered) {
      return;
    }
    _registrationState = SipRegistrationState.unregistering;
    _emitRegistration(
      SipRegistrationState.unregistering,
      message: 'Отмена регистрации...',
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));
    _registrationState = SipRegistrationState.unregistered;
    _emitRegistration(
      SipRegistrationState.unregistered,
      message: 'Регистрация снята',
    );
  }

  @override
  Future<String> startCall(String destination) async {
    await _ensureInitialized();
    final callId = await _generateCallId(destination);
    _emitCall(
      SipEventType.dialing,
      message: 'Набор $destination',
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));
    _emitCall(
      SipEventType.ringing,
      message: 'Звонок $destination',
    );
    return callId;
  }

  @override
  Future<void> hangup(String callId) async {
    if (_currentCallId != callId) {
      _emitError('Попытка завершить неизвестный вызов', callId: callId);
      return;
    }
    _emitCall(
      SipEventType.ended,
      message: 'Вызов завершён',
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));
    _currentCallId = null;
    _callState = SipCallState.none;
  }

  @override
  Future<void> sendDtmf(String callId, String digits) async {
    if (_currentCallId != callId || digits.isEmpty) {
      if (_currentCallId != callId) {
        _emitError('DTMF для неизвестного вызова', callId: callId);
      }
      return;
    }
    for (var i = 0; i < digits.length; i++) {
      final digit = digits[i];
      _emit(
        SipEvent(
          type: SipEventType.dtmf,
          callId: callId,
          digit: digit,
          message: 'DTMF $digit',
          callState: _callState,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  @override
  Future<void> dispose() async {
    await _eventController.close();
    _initialized = false;
    _currentCallId = null;
    _callState = SipCallState.none;
    _registrationState = SipRegistrationState.none;
  }
}
