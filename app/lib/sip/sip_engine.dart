import 'dart:async';
import 'package:flutter/services.dart';

/// Настройки SIP-коннекта для исходящего и входящего вызовов.
class SipConfig {
  const SipConfig({
    required this.domain,
    required this.port,
    required this.transport,
    required this.username,
    required this.password,
    this.outboundProxy,
    this.dtmfMode = 'rfc2833',
    this.stun,
    this.turn,
  });

  final String domain;
  final int port;
  final SipTransport transport;
  final String username;
  final String password;
  final String? outboundProxy;
  final String dtmfMode;
  final String? stun;
  final String? turn;
}

enum SipTransport { udp, tcp, tls }

enum SipEventType { dialing, ringing, connected, ended, dtmf }

class SipEvent {
  SipEvent({
    required this.callId,
    required this.type,
    required this.timestamp,
    this.message,
  });

  final String callId;
  final SipEventType type;
  final DateTime timestamp;
  final String? message;
}

abstract class SipEngine {
  /// События движка (регистрация, вызовы, DTMF).
  Stream<SipEvent> get events;

  Future<void> initialize(SipConfig config);
  Future<void> register();
  Future<void> unregister();

  Future<String> startCall(String destination);
  Future<void> acceptCall(String callId);
  Future<void> declineCall(String callId);
  Future<void> hangup(String callId);
  Future<void> setMute(String callId, bool mute);
  Future<void> setHold(String callId, bool hold);
  Future<void> setSpeaker(bool enable);
  Future<void> sendDtmf(String callId, String digits);

  void dispose();
}

class FakeSipEngine implements SipEngine {
  FakeSipEngine({
    this.dialingDelay = const Duration(seconds: 1),
    this.ringingDelay = const Duration(seconds: 2),
    this.connectedDelay = const Duration(seconds: 5),
  });

  final Duration dialingDelay;
  final Duration ringingDelay;
  final Duration connectedDelay;

  final _events = StreamController<SipEvent>.broadcast();
  final _timers = <String, List<Timer>>{};

  @override
  Stream<SipEvent> get events => _events.stream;

  @override
  Future<void> initialize(SipConfig config) async {
    // Расширение будет нужно при интеграции настоящего движка.
    _emit(
      'fake-init',
      SipEventType.dialing,
      message: 'initialized ${config.username}',
    );
    await Future.delayed(const Duration(milliseconds: 10));
  }

  @override
  Future<void> register() async {}

  @override
  Future<void> unregister() async {}

  @override
  Future<String> startCall(String destination) async {
    final callId = 'fake-${DateTime.now().millisecondsSinceEpoch}';

    _emit(callId, SipEventType.dialing, message: destination);

    _schedule(callId, dialingDelay, SipEventType.ringing, message: destination);
    _schedule(
      callId,
      dialingDelay + ringingDelay,
      SipEventType.connected,
      message: destination,
    );
    _schedule(
      callId,
      dialingDelay + ringingDelay + connectedDelay,
      SipEventType.ended,
      message: 'call ended',
    );

    return callId;
  }

  @override
  Future<void> hangup(String callId) async {
    _cancelTimers(callId);
    _emit(callId, SipEventType.ended, message: 'ended by local user');
  }

  @override
  Future<void> acceptCall(String callId) async {}

  @override
  Future<void> declineCall(String callId) async {}

  @override
  Future<void> setMute(String callId, bool mute) async {
    _emit(callId, SipEventType.dtmf, message: 'mute ${mute ? 'on' : 'off'}');
  }

  @override
  Future<void> setHold(String callId, bool hold) async {
    _emit(callId, SipEventType.dtmf, message: 'hold ${hold ? 'on' : 'off'}');
  }

  @override
  Future<void> setSpeaker(bool enable) async {
    _emit(
      'speaker',
      SipEventType.dtmf,
      message: 'speaker ${enable ? 'on' : 'off'}',
    );
  }

  @override
  Future<void> sendDtmf(String callId, String digits) async {
    _emit(callId, SipEventType.dtmf, message: 'dtmf $digits');
  }

  void _schedule(
    String callId,
    Duration delay,
    SipEventType type, {
    String? message,
  }) {
    final timer = Timer(delay, () => _emit(callId, type, message: message));
    _timers.putIfAbsent(callId, () => []).add(timer);
  }

  void _cancelTimers(String callId) {
    final timers = _timers.remove(callId);
    timers?.forEach((timer) => timer.cancel());
  }

  void _emit(String callId, SipEventType type, {String? message}) {
    if (_events.isClosed) return;
    _events.add(
      SipEvent(
        callId: callId,
        type: type,
        timestamp: DateTime.now(),
        message: message,
      ),
    );
  }

  @override
  void dispose() {
    for (final timers in _timers.values) {
      for (final timer in timers) {
        timer.cancel();
      }
    }
    _timers.clear();
    _events.close();
  }
}

/// Заглушка для будущей PJSIP-реализации через MethodChannel.
class PjsipSipEngine implements SipEngine {
  PjsipSipEngine()
    : _methodChannel = const MethodChannel('app/pjsip_engine'),
      _eventChannel = const EventChannel('app/pjsip_engine_events') {
    _eventsStream = _eventChannel.receiveBroadcastStream().map((event) {
      if (event is! Map) return null;
      final map = Map<String, dynamic>.from(event as Map);
      return SipEvent(
        callId: map['callId'] as String? ?? 'unknown',
        type: _mapType(map['type'] as String?),
        timestamp:
            DateTime.tryParse(map['timestamp'] as String? ?? '') ??
            DateTime.now(),
        message: map['message'] as String?,
      );
    }).whereType<SipEvent>();
  }

  final MethodChannel _methodChannel;
  final EventChannel _eventChannel;
  late final Stream<SipEvent> _eventsStream;

  @override
  Stream<SipEvent> get events => _eventsStream;

  @override
  Future<void> initialize(SipConfig config) async {
    await _methodChannel.invokeMethod('initialize', {
      'domain': config.domain,
      'port': config.port,
      'transport': config.transport.name,
      'username': config.username,
      'password': config.password,
    });
  }

  @override
  Future<void> register() => _methodChannel.invokeMethod('register');

  @override
  Future<void> unregister() => _methodChannel.invokeMethod('unregister');

  @override
  Future<String> startCall(String destination) async {
    final callId = await _methodChannel.invokeMethod<String>('startCall', {
      'destination': destination,
    });
    return callId ?? 'pjsip-${DateTime.now().millisecondsSinceEpoch}';
  }

  @override
  Future<void> acceptCall(String callId) =>
      _methodChannel.invokeMethod('acceptCall', {'callId': callId});

  @override
  Future<void> declineCall(String callId) =>
      _methodChannel.invokeMethod('declineCall', {'callId': callId});

  @override
  Future<void> hangup(String callId) =>
      _methodChannel.invokeMethod('hangup', {'callId': callId});

  @override
  Future<void> setMute(String callId, bool mute) =>
      _methodChannel.invokeMethod('setMute', {'callId': callId, 'mute': mute});

  @override
  Future<void> setHold(String callId, bool hold) =>
      _methodChannel.invokeMethod('setHold', {'callId': callId, 'hold': hold});

  @override
  Future<void> setSpeaker(bool enable) =>
      _methodChannel.invokeMethod('setSpeaker', {'enable': enable});

  @override
  Future<void> sendDtmf(String callId, String digits) => _methodChannel
      .invokeMethod('sendDtmf', {'callId': callId, 'digits': digits});

  SipEventType _mapType(String? raw) {
    switch (raw) {
      case 'dialing':
        return SipEventType.dialing;
      case 'ringing':
        return SipEventType.ringing;
      case 'connected':
        return SipEventType.connected;
      case 'ended':
        return SipEventType.ended;
      case 'dtmf':
      default:
        return SipEventType.dtmf;
    }
  }

  @override
  void dispose() {}
}
