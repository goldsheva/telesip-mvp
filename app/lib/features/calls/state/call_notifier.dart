import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:app/config/env_config.dart';
import 'package:app/core/providers/sip_providers.dart';
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
  });

  factory CallState.initial() => const CallState(calls: {}, errorMessage: null);

  final Map<String, CallInfo> calls;
  final String? activeCallId;
  final String? errorMessage;

  CallInfo? get activeCall => activeCallId != null ? calls[activeCallId] : null;

  List<CallInfo> get history =>
      calls.values.toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  CallState copyWith({
    Map<String, CallInfo>? calls,
    String? activeCallId,
    String? errorMessage,
  }) {
    return CallState(
      calls: calls ?? this.calls,
      activeCallId: activeCallId ?? this.activeCallId,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

class CallNotifier extends Notifier<CallState> {
  late final SipEngine _engine;
  ProviderSubscription<AsyncValue<SipEvent>>? _eventSubscription;
  bool _isRegistered = false;
  int? _registeredUserId;
  PbxSipUser? _lastKnownUser;

  Future<void> startCall(String destination) async {
    if (state.activeCallId != null) return;
    final trimmed = destination.trim();
    if (trimmed.isEmpty) return;
    if (!_isRegistered) {
      _setError('SIP не зарегистрирован');
      return;
    }
    final callId = await _engine.startCall(trimmed);
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
    ref.onDispose(() => _eventSubscription?.close());
    return CallState.initial();
  }

  void _onEvent(SipEvent event) {
    if (event.type == SipEventType.registration) {
      final registrationState = event.registrationState;
      if (registrationState == SipRegistrationState.registered) {
        _isRegistered = true;
        _registeredUserId = _lastKnownUser?.pbxSipUserId;
        _clearError();
      } else if (registrationState == SipRegistrationState.failed) {
        _isRegistered = false;
        _setError(event.message ?? 'Ошибка регистрации SIP');
      } else if (registrationState == SipRegistrationState.unregistered ||
          registrationState == SipRegistrationState.none) {
        _isRegistered = false;
        _registeredUserId = null;
      }
      return;
    }
    final callId = event.callId;
    if (callId == null) return;

    final status = _mapStatus(event.type);
    final previous = state.calls[callId];
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

    var activeCallId = state.activeCallId;
    if (status == CallStatus.ended) {
      if (activeCallId == callId) {
        activeCallId = null;
      }
    } else {
      activeCallId ??= callId;
    }

    final errorMessage =
        event.type == SipEventType.error ? event.message ?? 'SIP error' : null;
    state = state.copyWith(
      calls: updated,
      activeCallId: activeCallId,
      errorMessage: errorMessage,
    );
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
}

final callControllerProvider = NotifierProvider<CallNotifier, CallState>(
  CallNotifier.new,
);
