import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:app/config/env_config.dart';
import 'package:app/core/providers/sip_providers.dart';
import 'package:app/features/calls/call_watchdog.dart';
import 'package:app/features/sip_users/models/pbx_sip_user.dart';
import 'package:app/sip/sip_engine.dart';

enum CallStatus { dialing, ringing, connected, ended }

class CallInfo {
  const CallInfo({
    required this.id,
    required this.destination,
    required this.status,
    required this.createdAt,
    this.connectedAt,
    this.endedAt,
    this.timeline = const [],
    this.errorMessage,
  });

  final String id;
  final String destination;
  final CallStatus status;
  final DateTime createdAt;
  final DateTime? connectedAt;
  final DateTime? endedAt;
  final List<String> timeline;
  final String? errorMessage;

  CallInfo copyWith({
    String? destination,
    CallStatus? status,
    DateTime? connectedAt,
    DateTime? endedAt,
    List<String>? timeline,
    String? errorMessage,
  }) {
    return CallInfo(
      id: id,
      destination: destination ?? this.destination,
      status: status ?? this.status,
      createdAt: createdAt,
      connectedAt: connectedAt ?? this.connectedAt,
      endedAt: endedAt ?? this.endedAt,
      timeline: timeline ?? this.timeline,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

class CallState {
  const CallState({
    required this.calls,
    this.activeCallId,
    this.errorMessage,
    required this.watchdogState,
    required this.isRegistered,
  });

  factory CallState.initial() => CallState(
    calls: {},
    errorMessage: null,
    watchdogState: CallWatchdogState.ok(),
    isRegistered: false,
  );

  final Map<String, CallInfo> calls;
  final String? activeCallId;
  final String? errorMessage;
  final CallWatchdogState watchdogState;
  final bool isRegistered;

  CallInfo? get activeCall => activeCallId != null ? calls[activeCallId] : null;

  List<CallInfo> get history =>
      calls.values.toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  CallState copyWith({
    Map<String, CallInfo>? calls,
    String? activeCallId,
    String? errorMessage,
    CallWatchdogState? watchdogState,
    bool? isRegistered,
  }) {
    return CallState(
      calls: calls ?? this.calls,
      activeCallId: activeCallId ?? this.activeCallId,
      errorMessage: errorMessage ?? this.errorMessage,
      watchdogState: watchdogState ?? this.watchdogState,
      isRegistered: isRegistered ?? this.isRegistered,
    );
  }
}

class CallNotifier extends Notifier<CallState> {
  late final SipEngine _engine;
  ProviderSubscription<AsyncValue<SipEvent>>? _eventSubscription;
  bool _isRegistered = false;
  int? _registeredUserId;
  PbxSipUser? _lastKnownUser;
  Timer? _dialTimeoutTimer;
  String? _dialTimeoutCallId;
  CallWebRtcWatchdog? _webRtcWatchdog;
  String? _watchdogCallId;
  Timer? _watchdogFailureTimer;
  String? _failureTimerCallId;
  String? _pendingCallId;
  Timer? _registrationErrorTimer;
  String? _pendingRegistrationError;
  bool _userInitiatedRetry = false;
  Timer? _retrySuppressionTimer;
  bool _watchdogErrorActive = false;
  static const Duration _dialTimeout = Duration(seconds: 25);

  Future<void> startCall(String destination) async {
    final activeCall = state.activeCall;
    if (activeCall != null && activeCall.status != CallStatus.ended) return;
    final trimmed = destination.trim();
    if (trimmed.isEmpty) return;
    if (!_isRegistered) {
      _setError('SIP не зарегистрирован');
      return;
    }
    final callId = await _engine.startCall(trimmed);
    _pendingCallId = callId;
    _startDialTimeout(callId);
    _clearError();
    state = state.copyWith(activeCallId: callId);
  }

  Future<void> hangup(String callId) async {
    await _engine.hangup(callId);
  }

  Future<void> sendDtmf(String callId, String digits) async {
    if (digits.isEmpty) return;
    await _engine.sendDtmf(callId, digits);
  }

  Future<void> ensureRegistered(PbxSipUser user) async {
    _lastKnownUser = user;
    if (_isRegistered && _registeredUserId == user.pbxSipUserId) return;

    final wsConnections = user.sipConnections
        .where((c) => c.pbxSipProtocol.toLowerCase().contains('ws'))
        .toList();

    String wsUrl;
    String uriHost;

    if (wsConnections.isNotEmpty) {
      final connection = wsConnections.first;
      final protocol = connection.pbxSipProtocol.toLowerCase();
      final scheme = protocol.contains('wss')
          ? 'wss'
          : protocol.contains('ws')
          ? 'ws'
          : null;
      if (scheme == null) {
        _setError('Поддерживается только WS/WSS');
        return;
      }

      wsUrl = '$scheme://${connection.pbxSipUrl}:${connection.pbxSipPort}/';
      uriHost = Uri.tryParse(wsUrl)?.host ?? connection.pbxSipUrl;
    } else {
      final defaultWs = EnvConfig.sipWebSocketUrl;
      if (defaultWs == null) {
        _setError(
          'PBX не отдает WS/WSS transport. Для sip_ua нужен SIP over WebSocket. '
          'Ожидается WSS (например wss://pbx.teleleo.com:7443/).',
        );
        return;
      }
      wsUrl = defaultWs;
      uriHost = Uri.tryParse(wsUrl)?.host ?? '';
    }

    if (uriHost.isEmpty) {
      _setError('Невозможно определить домен SIP');
      return;
    }
    final uri = 'sip:${user.sipLogin}@$uriHost';
    try {
      _clearError();
      await _engine.register(
        uri: uri,
        password: user.sipPassword,
        wsUrl: wsUrl,
        displayName: user.sipLogin,
      );
    } catch (error) {
      _setError('Ошибка регистрации SIP: $error');
    }
  }

  @override
  CallState build() {
    _engine = ref.read(sipEngineProvider);
    _eventSubscription = ref.listen<AsyncValue<SipEvent>>(
      sipEventsProvider,
      (previous, next) => next.whenData(_onEvent),
    );
    ref.onDispose(() {
      _eventSubscription?.close();
      _disposeWatchdog();
      _cancelRegistrationErrorTimer();
    });
    return CallState.initial();
  }

  void _onEvent(SipEvent event) {
    if (event.type == SipEventType.registration) {
      final registrationState = event.registrationState;
      if (registrationState == SipRegistrationState.registered) {
        _isRegistered = true;
        _registeredUserId = _lastKnownUser?.pbxSipUserId;
        _cancelRegistrationErrorTimer();
        _pendingRegistrationError = null;
        _clearError();
      } else if (registrationState == SipRegistrationState.failed) {
        _isRegistered = false;
        _handleRegistrationFailure(event.message ?? 'Ошибка регистрации SIP');
      } else if (registrationState == SipRegistrationState.unregistered ||
          registrationState == SipRegistrationState.none) {
        _isRegistered = false;
        _registeredUserId = null;
      }
      state = state.copyWith(isRegistered: _isRegistered);
      return;
    }
    final callId = event.callId;
    if (callId == null) return;

    final status = _mapStatus(event.type);
    final pendingCallId = _pendingCallId;
    final previous =
        state.calls[callId] ??
        (pendingCallId != null ? state.calls[pendingCallId] : null);
    final destination = previous?.destination ?? event.message ?? 'call';
    final logs = List<String>.from(previous?.timeline ?? [])
      ..add(_describe(event));

    final updated = Map<String, CallInfo>.from(state.calls);
    updated[callId] = CallInfo(
      id: callId,
      destination: destination,
      status: status,
      createdAt: previous?.createdAt ?? event.timestamp,
      connectedAt: status == CallStatus.connected
          ? event.timestamp
          : previous?.connectedAt,
      endedAt: status == CallStatus.ended ? event.timestamp : previous?.endedAt,
      timeline: logs,
    );
    if (pendingCallId != null && pendingCallId != callId) {
      updated.remove(pendingCallId);
    }

    var activeCallId = state.activeCallId;
    if (status == CallStatus.ended) {
      if (activeCallId == callId || activeCallId == pendingCallId) {
        activeCallId = null;
      }
      _cancelDialTimeout();
      _pendingCallId = null;
    } else {
      if (status != CallStatus.dialing) {
        _cancelDialTimeout();
      }
      activeCallId = callId;
      if (_dialTimeoutCallId != null) {
        _dialTimeoutCallId = callId;
      }
      if (pendingCallId != null && pendingCallId != callId) {
        _pendingCallId = null;
      }
    }

    final errorMessage = event.type == SipEventType.error
        ? event.message ?? 'SIP error'
        : null;
    final previousState = state;
    state = state.copyWith(
      calls: updated,
      activeCallId: activeCallId,
      errorMessage: errorMessage,
    );
    _handleWatchdogActivation(previousState, state);
  }

  CallStatus _mapStatus(SipEventType event) {
    switch (event) {
      case SipEventType.dialing:
        return CallStatus.dialing;
      case SipEventType.ringing:
        return CallStatus.ringing;
      case SipEventType.connected:
        return CallStatus.connected;
      case SipEventType.ended:
        return CallStatus.ended;
      case SipEventType.dtmf:
        return CallStatus.connected;
      case SipEventType.registration:
        return CallStatus.ended;
      case SipEventType.error:
        return CallStatus.ended;
    }
  }

  String _describe(SipEvent event) {
    final payload = event.message != null ? ' (${event.message})' : '';
    return '${event.type.name.toUpperCase()}$payload';
  }

  void _setError(String message) {
    state = state.copyWith(errorMessage: message);
  }

  void _clearError() {
    if (state.errorMessage != null) {
      state = state.copyWith(errorMessage: null);
    }
  }

  void _handleRegistrationFailure(String message) {
    _pendingRegistrationError = message;
    _cancelRegistrationErrorTimer();
    _registrationErrorTimer = Timer(const Duration(seconds: 2), () {
      if (_isRegistered) {
        _pendingRegistrationError = null;
        return;
      }
      _setError(_pendingRegistrationError ?? 'Ошибка регистрации SIP');
    });
  }

  void _cancelRegistrationErrorTimer() {
    _registrationErrorTimer?.cancel();
    _registrationErrorTimer = null;
  }

  void _startDialTimeout(String callId) {
    _cancelDialTimeout();
    _dialTimeoutCallId = callId;
    _dialTimeoutTimer = Timer(_dialTimeout, () async {
      final targetCallId = _dialTimeoutCallId;
      if (targetCallId == null) return;
      if (state.activeCallId != targetCallId) return;
      _setError('Вызов не был принят, завершаем');
      await _engine.hangup(targetCallId);
      _cancelDialTimeout();
    });
  }

  void _cancelDialTimeout() {
    _dialTimeoutTimer?.cancel();
    _dialTimeoutTimer = null;
    _dialTimeoutCallId = null;
  }

  void _handleWatchdogActivation(CallState previous, CallState next) {
    final prevStatus = previous.activeCall?.status;
    final nextStatus = next.activeCall?.status;
    final hadConnected = prevStatus == CallStatus.connected;
    final hasConnected = nextStatus == CallStatus.connected;

    if (hasConnected && !hadConnected) {
      final callId = next.activeCall?.id;
      if (callId != null) {
        _attachWatchdog(callId);
      }
    } else if (!hasConnected && hadConnected) {
      _disposeWatchdog();
    }
  }

  void _attachWatchdog(String callId) {
    if (_watchdogCallId == callId) return;
    _disposeWatchdog();
    final call = _engine.getCall(callId);
    if (call == null || call.peerConnection == null) return;
    _webRtcWatchdog = CallWebRtcWatchdog(
      call: call,
      onStateChange: _handleWatchdogStateChange,
      onFailed: () => _handleWatchdogFailure(callId),
    );
    _watchdogCallId = callId;
    _handleWatchdogStateChange(CallWatchdogState.ok());
    debugPrint('Watchdog attached for call $callId');
  }

  void _handleWatchdogStateChange(CallWatchdogState newState) {
    debugPrint(
      'Watchdog($_watchdogCallId) state -> ${newState.status}: ${newState.message}',
    );
    state = state.copyWith(watchdogState: newState);
    if (newState.status == CallWatchdogStatus.failed &&
        state.activeCall?.status == CallStatus.connected &&
        !_userInitiatedRetry) {
      _startFailureTimer(state.activeCall!.id);
    } else if (newState.status == CallWatchdogStatus.ok) {
      _cancelFailureTimer();
    }
    if (newState.status == CallWatchdogStatus.ok) {
      _userInitiatedRetry = false;
      _cancelRetrySuppressionTimer();
      _clearWatchdogError();
    }
  }

  void _handleWatchdogFailure(String callId) {
    if (state.activeCall?.id != callId) return;
    debugPrint('Watchdog failure triggered for $callId');
    _watchdogErrorActive = true;
    state = state.copyWith(
      errorMessage: 'Сеть нестабильна',
      watchdogState: CallWatchdogState.failed(),
    );
  }

  void _startFailureTimer(String callId) {
    if (_failureTimerCallId == callId) return;
    _cancelFailureTimer();
    _failureTimerCallId = callId;
    _watchdogFailureTimer = Timer(const Duration(seconds: 20), () {
      if (_failureTimerCallId != callId) return;
      if (state.activeCall?.id != callId) return;
      if (state.watchdogState.status != CallWatchdogStatus.failed) return;
      if (_userInitiatedRetry) {
        debugPrint('Watchdog hangup suppressed for $callId (user retry)');
        return;
      }
      debugPrint('Watchdog hangup timer expired for $callId');
      _watchdogErrorActive = true;
      _setError('Сеть нестабильна, завершаем вызов');
      _engine.hangup(callId);
    });
    debugPrint('Watchdog failure timer started for $callId');
  }

  void _cancelFailureTimer() {
    if (_watchdogFailureTimer != null) {
      debugPrint(
        'Watchdog failure timer cancelled for ${_failureTimerCallId ?? _watchdogCallId}',
      );
    }
    _watchdogFailureTimer?.cancel();
    _watchdogFailureTimer = null;
    _failureTimerCallId = null;
  }

  void _startRetrySuppressionTimer() {
    _retrySuppressionTimer?.cancel();
    _retrySuppressionTimer = Timer(const Duration(seconds: 10), () {
      debugPrint('Retry suppression ended for $_watchdogCallId');
      _userInitiatedRetry = false;
      _retrySuppressionTimer = null;
      if (state.watchdogState.status == CallWatchdogStatus.failed &&
          state.activeCall?.status == CallStatus.connected) {
        _startFailureTimer(state.activeCall!.id);
      }
    });
    debugPrint('Retry suppression timer started for $_watchdogCallId');
  }

  void _cancelRetrySuppressionTimer() {
    if (_retrySuppressionTimer != null) {
      debugPrint('Retry suppression timer cancelled for $_watchdogCallId');
    }
    _retrySuppressionTimer?.cancel();
    _retrySuppressionTimer = null;
  }

  void _clearWatchdogError() {
    if (_watchdogErrorActive &&
        (state.errorMessage == 'Сеть нестабильна' ||
            state.errorMessage == 'Сеть нестабильна, завершаем вызов')) {
      state = state.copyWith(errorMessage: null);
    }
    _watchdogErrorActive = false;
  }

  void _disposeWatchdog() {
    _webRtcWatchdog?.dispose();
    _webRtcWatchdog = null;
    _watchdogCallId = null;
    _cancelFailureTimer();
    _cancelRetrySuppressionTimer();
    _userInitiatedRetry = false;
    _clearWatchdogError();
    if (state.watchdogState.status != CallWatchdogStatus.ok) {
      state = state.copyWith(watchdogState: CallWatchdogState.ok());
    }
  }

  Future<void> retryCallAudio() async {
    if (_webRtcWatchdog == null) return;
    _userInitiatedRetry = true;
    _cancelFailureTimer();
    _startRetrySuppressionTimer();
    await _webRtcWatchdog!.manualRestart();
  }
}

final callControllerProvider = NotifierProvider<CallNotifier, CallState>(
  CallNotifier.new,
);
