import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:app/sip/sip_engine.dart';

import 'sip_engine_providers.dart';

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
  });

  final String id;
  final String destination;
  final CallStatus status;
  final DateTime createdAt;
  final DateTime? connectedAt;
  final DateTime? endedAt;
  final List<String> timeline;

  CallInfo copyWith({
    String? destination,
    CallStatus? status,
    DateTime? connectedAt,
    DateTime? endedAt,
    List<String>? timeline,
  }) {
    return CallInfo(
      id: id,
      destination: destination ?? this.destination,
      status: status ?? this.status,
      createdAt: createdAt,
      connectedAt: connectedAt ?? this.connectedAt,
      endedAt: endedAt ?? this.endedAt,
      timeline: timeline ?? this.timeline,
    );
  }
}

class CallState {
  const CallState({required this.calls, this.activeCallId});

  factory CallState.initial() => const CallState(calls: {});

  final Map<String, CallInfo> calls;
  final String? activeCallId;

  CallInfo? get activeCall => activeCallId != null ? calls[activeCallId] : null;

  List<CallInfo> get history =>
      calls.values.toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  CallState copyWith({Map<String, CallInfo>? calls, String? activeCallId}) {
    return CallState(
      calls: calls ?? this.calls,
      activeCallId: activeCallId ?? this.activeCallId,
    );
  }
}

class CallNotifier extends StateNotifier<CallState> {
  CallNotifier(this._engine) : super(CallState.initial()) {
    _subscription = _engine.events.listen(_onEvent);
  }

  final SipEngine _engine;
  late final StreamSubscription<SipEvent> _subscription;

  Future<void> startCall(String destination) async {
    final trimmed = destination.trim();
    if (trimmed.isEmpty) return;
    final callId = await _engine.startCall(trimmed);
    state = state.copyWith(activeCallId: callId);
  }

  Future<void> hangup(String callId) async {
    await _engine.hangup(callId);
  }

  Future<void> sendDtmf(String callId, String digits) async {
    if (digits.isEmpty) return;
    await _engine.sendDtmf(callId, digits);
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }

  void _onEvent(SipEvent event) {
    final status = _mapStatus(event.type);
    final previous = state.calls[event.callId];
    final destination = previous?.destination ?? event.message ?? 'call';
    final logs = List<String>.from(previous?.timeline ?? [])
      ..add(_describe(event));

    final updated = Map<String, CallInfo>.from(state.calls);
    updated[event.callId] = CallInfo(
      id: event.callId,
      destination: destination,
      status: status,
      createdAt: previous?.createdAt ?? event.timestamp,
      connectedAt: status == CallStatus.connected
          ? event.timestamp
          : previous?.connectedAt,
      endedAt: status == CallStatus.ended ? event.timestamp : previous?.endedAt,
      timeline: logs,
    );

    final activeCallId =
        status == CallStatus.ended && state.activeCallId == event.callId
        ? null
        : state.activeCallId ?? event.callId;

    state = state.copyWith(calls: updated, activeCallId: activeCallId);
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
      default:
        return CallStatus.connected;
    }
  }

  String _describe(SipEvent event) {
    final payload = event.message != null ? ' (${event.message})' : '';
    return '${event.type.name.toUpperCase()}$payload';
  }
}

final callControllerProvider = StateNotifierProvider<CallNotifier, CallState>((
  ref,
) {
  final engine = ref.watch(sipEngineProvider);
  return CallNotifier(engine);
});
