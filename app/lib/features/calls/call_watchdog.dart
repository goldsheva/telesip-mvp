import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:sip_ua/sip_ua.dart';

enum CallWatchdogStatus { ok, reconnecting, failed }

class CallWatchdogState {
  final CallWatchdogStatus status;
  final String message;

  const CallWatchdogState(this.status, this.message);

  factory CallWatchdogState.ok([String message = 'Соединение стабильно']) =>
      CallWatchdogState(CallWatchdogStatus.ok, message);

  factory CallWatchdogState.reconnecting([
    String message = 'Перезапуск ICE...',
  ]) => CallWatchdogState(CallWatchdogStatus.reconnecting, message);

  factory CallWatchdogState.failed([String message = 'Сеть нестабильна']) =>
      CallWatchdogState(CallWatchdogStatus.failed, message);
}

class CallWebRtcWatchdog {
  CallWebRtcWatchdog({
    required Call call,
    required void Function(CallWatchdogState) onStateChange,
    required VoidCallback onFailed,
  }) : _call = call,
       _onStateChange = onStateChange,
       _onFailed = onFailed {
    _pc = call.peerConnection;
    _attachListeners();
  }

  static const _staleThreshold = Duration(seconds: 7);
  static const _restartInterval = Duration(seconds: 15);
  static const _maxAttempts = 2;

  final Call _call;
  final void Function(CallWatchdogState) _onStateChange;
  final VoidCallback _onFailed;

  RTCPeerConnection? _pc;
  Timer? _staleTimer;
  bool _disposed = false;
  bool _restartInProgress = false;
  int _restartAttempts = 0;
  DateTime? _lastRestartAt;
  CallWatchdogState _currentState = CallWatchdogState.ok();
  bool _failedNotified = false;
  RTCSignalingState _signalingState = RTCSignalingState.RTCSignalingStateStable;
  RTCIceConnectionState? _currentIceState;

  void _attachListeners() {
    if (_pc == null) return;
    _pc!.onIceConnectionState = _onIceConnectionState;
    _pc!.onConnectionState = _onConnectionState;
    _pc!.onSignalingState = _onSignalingState;
  }

  void _onIceConnectionState(RTCIceConnectionState state) {
    if (_disposed) return;
    _currentIceState = state;
    if (state == RTCIceConnectionState.RTCIceConnectionStateChecking ||
        state == RTCIceConnectionState.RTCIceConnectionStateDisconnected) {
      _scheduleStaleTimer(state);
    } else {
      _cancelStaleTimer();
    }
    if (state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
      _attemptRestart('ICE failed');
    } else if (state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
        state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
      _setState(CallWatchdogState.ok('ICE ${_stateLabel(state)}'));
    }
  }

  void _onConnectionState(RTCPeerConnectionState state) {
    if (_disposed) return;
    if (state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
      _scheduleStaleTimer(null);
    }
    if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
      _setState(CallWatchdogState.ok('Connection established'));
    }
  }

  void _onSignalingState(RTCSignalingState state) {
    if (_disposed) return;
    _signalingState = state;
  }

  void _scheduleStaleTimer(RTCIceConnectionState? state) {
    _cancelStaleTimer();
    _staleTimer = Timer(_staleThreshold, () {
      final current = _currentIceState;
      if (current == RTCIceConnectionState.RTCIceConnectionStateChecking ||
          current == RTCIceConnectionState.RTCIceConnectionStateDisconnected) {
        _attemptRestart('ICE stuck ${_stateLabel(current)}');
      }
    });
  }

  void _cancelStaleTimer() {
    _staleTimer?.cancel();
    _staleTimer = null;
  }

  Future<void> _attemptRestart(String reason) async {
    if (_disposed) return;
    if (_currentState.status == CallWatchdogStatus.failed) return;
    if (_restartAttempts >= _maxAttempts) {
      _setState(CallWatchdogState.failed());
      if (!_failedNotified) {
        _failedNotified = true;
        _onFailed();
      }
      return;
    }
    final now = DateTime.now();
    if (_lastRestartAt != null &&
        now.difference(_lastRestartAt!) < _restartInterval) {
      return;
    }
    if (_restartInProgress) return;
    _restartAttempts++;
    _lastRestartAt = now;
    _setState(
      CallWatchdogState.reconnecting(
        'Перезапуск ICE (#$_restartAttempts): $reason',
      ),
    );
    _restartInProgress = true;
    try {
      if (_pc != null) {
        await _pc!.restartIce();
      }
    } on Object catch (_) {
      await _legacyRestart();
    } finally {
      _restartInProgress = false;
    }
  }

  Future<void> _legacyRestart() async {
    if (_signalingState != RTCSignalingState.RTCSignalingStateStable) {
      return;
    }
    final completer = Completer<void>();
    _call.renegotiate(
      options: {'iceRestart': true},
      done: (_) {
        if (!completer.isCompleted) {
          completer.complete();
        }
      },
    );
    try {
      await completer.future.timeout(const Duration(seconds: 6));
    } catch (_) {
      // best-effort
    }
  }

  Future<void> manualRestart() async {
    await _attemptRestart('ручная попытка');
  }

  String _stateLabel(RTCIceConnectionState? state) {
    if (state == null) return 'unknown';
    return state.toString().split('.').last;
  }

  void _setState(CallWatchdogState state) {
    if (_disposed) return;
    if (_currentState.status == state.status &&
        _currentState.message == state.message) {
      return;
    }
    _currentState = state;
    _onStateChange(state);
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _cancelStaleTimer();
    if (_pc != null) {
      _pc!.onIceConnectionState = null;
      _pc!.onConnectionState = null;
      _pc!.onSignalingState = null;
    }
  }
}
