import 'dart:async';

import 'package:sip_ua/sip_ua.dart';

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

class SipUaEngine implements SipEngine, SipUaHelperListener {
  final StreamController<SipEvent> _eventController =
      StreamController<SipEvent>.broadcast();
  final SIPUAHelper _helper = SIPUAHelper();
  final Map<String, Call> _callReferences = <String, Call>{};
  final Map<String, String> _callIdAliases = <String, String>{};

  bool _initialized = false;
  String? _currentCallId;
  SipRegistrationState _registrationState = SipRegistrationState.none;
  SipCallState _callState = SipCallState.none;
  String? _registrationDomain;

  @override
  Stream<SipEvent> get events => _eventController.stream;

  void _emit(SipEvent event) {
    if (_eventController.isClosed) return;
    _eventController.add(event);
  }

  void _emitRegistration(SipRegistrationState state, {String? message}) {
    _registrationState = state;
    _emit(
      SipEvent(
        type: SipEventType.registration,
        callId: null,
        registrationState: state,
        message: message,
      ),
    );
  }

  void _emitCall(SipEventType type, {String? callId, String? message}) {
    final activeCallId = callId ?? _currentCallId;
    if (activeCallId == null) return;
    _callState = _callStateFromEvent(type);
    _emit(
      SipEvent(
        type: type,
        callId: activeCallId,
        callState: _callState,
        message: message,
      ),
    );
  }

  void _emitError(String message, {String? callId}) {
    _callState = SipCallState.failed;
    _emit(
      SipEvent(
        type: SipEventType.error,
        callId: callId,
        callState: _callState,
        message: message,
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

  SipEventType _eventTypeFromCallState(CallStateEnum? state) {
    switch (state) {
      case CallStateEnum.CALL_INITIATION:
      case CallStateEnum.CONNECTING:
      case CallStateEnum.NONE:
        return SipEventType.dialing;
      case CallStateEnum.PROGRESS:
        return SipEventType.ringing;
      case CallStateEnum.ACCEPTED:
      case CallStateEnum.CONFIRMED:
      case CallStateEnum.STREAM:
      case CallStateEnum.UNMUTED:
      case CallStateEnum.MUTED:
      case CallStateEnum.HOLD:
      case CallStateEnum.UNHOLD:
      case CallStateEnum.REFER:
        return SipEventType.connected;
      case CallStateEnum.ENDED:
        return SipEventType.ended;
      case CallStateEnum.FAILED:
        return SipEventType.error;
      default:
        return SipEventType.dialing;
    }
  }

  String _buildCallId() => 'call-${DateTime.now().millisecondsSinceEpoch}';

  String _normalizeDestination(String destination) {
    final trimmed = destination.trim();
    if (trimmed.isEmpty) return trimmed;
    if (trimmed.toLowerCase().startsWith('sip:')) {
      return trimmed;
    }
    if (trimmed.contains('@')) {
      return trimmed.startsWith('sip:') ? trimmed : 'sip:$trimmed';
    }
    if (_registrationDomain != null && _registrationDomain!.isNotEmpty) {
      return 'sip:$trimmed@$_registrationDomain';
    }
    return trimmed;
  }

  String? _extractDomain(String uri) {
    final atIndex = uri.indexOf('@');
    if (atIndex < 0) return null;
    var domain = uri.substring(atIndex + 1);
    for (final delimiter in [';', '/', ':']) {
      final index = domain.indexOf(delimiter);
      if (index >= 0) {
        domain = domain.substring(0, index);
      }
    }
    return domain.isNotEmpty ? domain : null;
  }

  String? _extractSipLogin(String uri) {
    var cleaned = uri;
    if (cleaned.startsWith('sip:')) {
      cleaned = cleaned.substring(4);
    }
    final atIndex = cleaned.indexOf('@');
    if (atIndex <= 0) return null;
    return cleaned.substring(0, atIndex);
  }

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    await init();
  }

  @override
  Future<void> init() async {
    if (_initialized) return;
    _helper.addSipUaHelperListener(this);
    _initialized = true;
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

    final normalizedUri = uri.trim();
    _registrationDomain = _extractDomain(normalizedUri);
    _registrationState = SipRegistrationState.registering;
    _emitRegistration(
      SipRegistrationState.registering,
      message: displayName != null && displayName.isNotEmpty
          ? 'Регистрируемся как $displayName'
          : 'Регистрируемся...',
    );

    final settings = UaSettings()
      ..uri = normalizedUri
      ..password = password
      ..webSocketUrl = wsUrl.trim()
      ..displayName = displayName
      ..transportType = TransportType.WS
      ..authorizationUser = _extractSipLogin(normalizedUri)
      ..register = true;

    try {
      await _helper.start(settings);
      _helper.register();
    } catch (error) {
      _emitRegistration(SipRegistrationState.failed, message: error.toString());
      _emitError('Ошибка регистрации SIP: $error');
    }
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
    try {
      await _helper.unregister();
      _registrationState = SipRegistrationState.unregistered;
      _emitRegistration(
        SipRegistrationState.unregistered,
        message: 'Регистрация снята',
      );
    } catch (error) {
      _registrationState = SipRegistrationState.failed;
      _emitRegistration(SipRegistrationState.failed, message: error.toString());
    } finally {
      _helper.stop();
    }
  }

  @override
  Future<String> startCall(String destination) async {
    await _ensureInitialized();
    final target = _normalizeDestination(destination);
    final callId = _buildCallId();
    _currentCallId = callId;
    _callState = SipCallState.dialing;
    _emitCall(SipEventType.dialing, callId: callId, message: 'Набор $target');
    if (_registrationState != SipRegistrationState.registered) {
      _emitError('SIP не зарегистрирован', callId: callId);
      _cleanupCall(callId, callId);
      return callId;
    }
    final started = await _helper.call(target, voiceOnly: true);
    if (!started) {
      _emitError('Не удалось начать вызов', callId: callId);
      _emitCall(SipEventType.ended, callId: callId, message: 'Вызов не пошёл');
      _cleanupCall(callId, callId);
    }
    return callId;
  }

  @override
  Future<void> hangup(String callId) async {
    final resolveId = _callIdAliases[callId] ?? callId;
    final call = _callReferences[resolveId];
    call?.hangup();
  }

  @override
  Future<void> sendDtmf(String callId, String digits) async {
    if (digits.isEmpty) return;
    final resolveId = _callIdAliases[callId] ?? callId;
    final call = _callReferences[resolveId];
    if (call == null) return;
    for (var i = 0; i < digits.length; i++) {
      final digit = digits[i];
      call.sendDTMF(digit);
      _emit(
        SipEvent(
          type: SipEventType.dtmf,
          callId: resolveId,
          digit: digit,
          message: 'DTMF $digit',
          callState: _callState,
        ),
      );
    }
  }

  @override
  Future<void> dispose() async {
    _helper.removeSipUaHelperListener(this);
    _helper.stop();
    await _eventController.close();
    _initialized = false;
    _currentCallId = null;
    _callReferences.clear();
    _callState = SipCallState.none;
    _registrationState = SipRegistrationState.none;
  }

  @override
  void transportStateChanged(TransportState state) {}

  @override
  void registrationStateChanged(RegistrationState state) {
    final newState = _mapRegistrationState(state.state);
    final message = state.cause?.cause ?? state.cause?.reason_phrase;
    _emitRegistration(newState, message: message);
  }

  @override
  void callStateChanged(Call call, CallState state) {
    final pendingId = _currentCallId;
    final realId = (call.id != null && call.id!.isNotEmpty)
        ? call.id!
        : pendingId;
    if (realId == null || realId.isEmpty) return;
    if (pendingId != null && realId != pendingId) {
      _callIdAliases[pendingId] = realId;
    }
    _callReferences[realId] = call;
    final nextState = state.state;
    final eventType = _eventTypeFromCallState(nextState);
    final message =
        state.cause?.cause ?? state.cause?.reason_phrase ?? nextState.name;
    if (eventType == SipEventType.error) {
      _emitError(message, callId: realId);
      _cleanupCall(pendingId, realId);
      return;
    }
    _emitCall(eventType, callId: realId, message: message);
    if (eventType == SipEventType.ended) {
      _cleanupCall(pendingId, realId);
    }
  }

  void _cleanupCall(String? pendingId, String realId) {
    _callReferences.remove(realId);
    if (pendingId != null) {
      _callReferences.remove(pendingId);
      _callIdAliases.remove(pendingId);
    }
    if (_currentCallId == pendingId || _currentCallId == realId) {
      _currentCallId = null;
    }
  }

  @override
  void onNewMessage(SIPMessageRequest msg) {}

  @override
  void onNewNotify(Notify ntf) {}

  @override
  void onNewReinvite(ReInvite event) {}

  SipRegistrationState _mapRegistrationState(RegistrationStateEnum? state) {
    switch (state) {
      case RegistrationStateEnum.REGISTERED:
        return SipRegistrationState.registered;
      case RegistrationStateEnum.UNREGISTERED:
        return SipRegistrationState.unregistered;
      case RegistrationStateEnum.REGISTRATION_FAILED:
        return SipRegistrationState.failed;
      case RegistrationStateEnum.NONE:
      default:
        return SipRegistrationState.none;
    }
  }
}
