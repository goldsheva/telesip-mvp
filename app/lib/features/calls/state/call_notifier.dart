import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:app/config/env_config.dart';
import 'package:app/core/providers.dart';
import 'package:app/core/providers/sip_providers.dart';
import 'package:app/core/storage/fcm_storage.dart';
import 'package:app/core/storage/sip_auth_storage.dart';
import 'package:app/features/calls/call_watchdog.dart';
import 'package:app/features/sip_users/models/pbx_sip_user.dart';
import 'package:app/services/audio_focus_service.dart';
import 'package:app/sip/sip_engine.dart';

CallNotifier? _globalCallNotifierInstance;

void _registerGlobalCallNotifierInstance(CallNotifier notifier) {
  _globalCallNotifierInstance = notifier;
}

void _unregisterGlobalCallNotifierInstance(CallNotifier notifier) {
  if (_globalCallNotifierInstance == notifier) {
    _globalCallNotifierInstance = null;
  }
}

Future<void> requestIncomingCallHintProcessing() async {
  final handler = _globalCallNotifierInstance;
  if (handler == null) return;
  await handler.handleIncomingCallHintIfAny();
}

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
    this.dongleId,
  });

  final String id;
  final String destination;
  final CallStatus status;
  final DateTime createdAt;
  final DateTime? connectedAt;
  final DateTime? endedAt;
  final List<String> timeline;
  final String? errorMessage;
  final int? dongleId;

  CallInfo copyWith({
    String? destination,
    CallStatus? status,
    DateTime? connectedAt,
    DateTime? endedAt,
    List<String>? timeline,
    String? errorMessage,
    int? dongleId,
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
      dongleId: dongleId ?? this.dongleId,
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
  final Map<String, int?> _callDongleMap = {};
  bool _userInitiatedRetry = false;
  Timer? _retrySuppressionTimer;
  bool _watchdogErrorActive = false;
  bool _audioFocusHeld = false;
  String? _focusedCallId;
  static const Duration _dialTimeout = Duration(seconds: 25);
  final Map<String, DateTime> _busyRejected = {};
  static const Duration _busyRejectTtl = Duration(seconds: 90);
  final Map<String, DateTime> _recentlyEnded = {};
  static const Duration _recentlyEndedTtl = Duration(seconds: 90);
  DateTime? _lastStrayRingingRejectAt;
  static const Duration _strayRingingRejectMinGap = Duration(seconds: 2);
  DateTime? _busyUntil;
  static const Duration _busyGrace = Duration(seconds: 2);

  DateTime? _lastHandledHintTimestamp;
  DateTime? _lastHintAttemptAt;
  bool _isHandlingHint = false;
  static const Duration _incomingHintExpiry = Duration(seconds: 60);
  static const Duration _incomingHintRetryTtl = Duration(seconds: 30);

  bool get isBusy {
    final baseBusy =
        state.activeCall != null &&
        state.activeCall!.status != CallStatus.ended;
    final graceBusy =
        _busyUntil != null && DateTime.now().isBefore(_busyUntil!);
    return baseBusy || graceBusy;
  }

  Future<void> startCall(String destination) async {
    final activeCall = state.activeCall;
    if (activeCall != null && activeCall.status != CallStatus.ended) return;
    final trimmed = destination.trim();
    if (trimmed.isEmpty) return;
    if (!_isRegistered) {
      _setError('SIP is not registered');
      return;
    }
    final callId = await _engine.startCall(trimmed);
    _pendingCallId = callId;
    _callDongleMap[callId] = _lastKnownUser?.dongleId;
    _startDialTimeout(callId);
    _clearError();
    state = state.copyWith(activeCallId: callId);
    unawaited(_ensureAudioFocus(callId));
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
        _setError('Only WS/WSS transports are supported');
        return;
      }

      wsUrl = '$scheme://${connection.pbxSipUrl}:${connection.pbxSipPort}/';
      uriHost = Uri.tryParse(wsUrl)?.host ?? connection.pbxSipUrl;
    } else {
      final defaultWs = EnvConfig.sipWebSocketUrl;
      if (defaultWs == null) {
        _setError(
          'PBX does not offer WS/WSS transport. Sip_ua requires SIP over WebSocket. '
          'Expected WSS (e.g., wss://pbx.teleleo.com:7443/).',
        );
        return;
      }
      wsUrl = defaultWs;
      uriHost = Uri.tryParse(wsUrl)?.host ?? '';
    }

    if (uriHost.isEmpty) {
      _setError('Unable to determine SIP domain');
      return;
    }
    final uri = 'sip:${user.sipLogin}@$uriHost';
    final snapshot = SipAuthSnapshot(
      uri: uri,
      password: user.sipPassword,
      wsUrl: wsUrl,
      displayName: user.sipLogin,
      timestamp: DateTime.now(),
    );
    try {
      _clearError();
      await _engine.register(
        uri: uri,
        password: user.sipPassword,
        wsUrl: wsUrl,
        displayName: user.sipLogin,
      );
      await ref.read(sipAuthStorageProvider).writeSnapshot(snapshot);
    } catch (error) {
      _setError('SIP registration failed: $error');
    }
  }

  Future<bool> registerWithSnapshot(SipAuthSnapshot snapshot) async {
    if (_isRegistered) {
      debugPrint(
        '[INCOMING] already registered; treating wake hint as handled',
      );
      return true;
    }

    _clearError();
    try {
      await _engine.register(
        uri: snapshot.uri,
        password: snapshot.password,
        wsUrl: snapshot.wsUrl,
        displayName: snapshot.displayName,
      );
      debugPrint(
        '[INCOMING] SIP register triggered from wake hint (uri=${snapshot.uri})',
      );
      return true;
    } catch (error) {
      _setError('SIP registration failed: $error');
      return false;
    }
  }

  Future<void> handleIncomingCallHintIfAny() async {
    if (_isHandlingHint) return;
    _isHandlingHint = true;
    try {
      final raw = await FcmStorage.readPendingIncomingHint();
      if (raw == null) return;

      final payload = raw['payload'] as Map<String, dynamic>?;
      final timestampRaw = raw['timestamp'] as String?;
      final timestamp = DateTime.tryParse(timestampRaw ?? '');
      final callUuid = payload?['call_uuid']?.toString() ?? '<none>';

      if (payload == null || timestamp == null) {
        debugPrint(
          '[INCOMING] invalid pending hint (call_uuid=$callUuid), clearing',
        );
        await FcmStorage.clearPendingIncomingHint();
        return;
      }

      final now = DateTime.now();
      if (now.difference(timestamp) > _incomingHintExpiry) {
        debugPrint(
          '[INCOMING] pending hint expired after ${now.difference(timestamp).inSeconds}s (call_uuid=$callUuid)',
        );
        await FcmStorage.clearPendingIncomingHint();
        return;
      }

      if (_lastHandledHintTimestamp != null &&
          _lastHandledHintTimestamp!.isAtSameMomentAs(timestamp)) {
        return;
      }

      if (_lastHintAttemptAt != null &&
          now.difference(_lastHintAttemptAt!) < _incomingHintRetryTtl) {
        final remaining =
            _incomingHintRetryTtl - now.difference(_lastHintAttemptAt!);
        debugPrint(
          '[INCOMING] hint retry suppressed for ${remaining.inSeconds}s (call_uuid=$callUuid)',
        );
        return;
      }

      if (isBusy) {
        debugPrint(
          '[INCOMING] busy when handling hint (call_uuid=$callUuid), will retry later',
        );
        return;
      }

      final snapshot = await ref.read(sipAuthStorageProvider).readSnapshot();
      if (snapshot == null) {
        debugPrint(
          '[INCOMING] no stored SIP credentials to register (call_uuid=$callUuid)',
        );
        return;
      }

      _lastHintAttemptAt = now;
      debugPrint('[INCOMING] registering SIP from hint (call_uuid=$callUuid)');
      final registered = await registerWithSnapshot(snapshot);
      if (registered) {
        _lastHandledHintTimestamp = timestamp;
        await FcmStorage.clearPendingIncomingHint();
        debugPrint(
          '[INCOMING] pending hint handled and cleared (call_uuid=$callUuid)',
        );
      } else {
        debugPrint(
          '[INCOMING] hint handling failed, retry allowed after ${_incomingHintRetryTtl.inSeconds}s (call_uuid=$callUuid)',
        );
      }
    } finally {
      _isHandlingHint = false;
    }
  }

  Future<void> _ensureAudioFocus(String callId) async {
    if (_audioFocusHeld && _focusedCallId == callId) return;
    try {
      await AudioFocusService.acquire(callId: callId);
      _audioFocusHeld = true;
      _focusedCallId = callId;
    } catch (error) {
      debugPrint('[AUDIO_FOCUS] acquire failed for $callId: $error');
      _audioFocusHeld = false;
      _focusedCallId = null;
    }
  }

  Future<void> _releaseAudioFocus() async {
    if (!_audioFocusHeld && _focusedCallId == null) return;
    try {
      await AudioFocusService.release();
    } catch (error) {
      debugPrint('[AUDIO_FOCUS] release failed: $error');
    } finally {
      _audioFocusHeld = false;
      _focusedCallId = null;
    }
  }

  Future<void> answerFromNotification(String callId) async {
    final callInfo = state.calls[callId];
    if (callInfo == null || callInfo.status == CallStatus.ended) {
      return;
    }
    final call = _engine.getCall(callId);
    if (call == null) {
      debugPrint('[CALLS] answerFromNotification unknown call $callId');
      return;
    }
    try {
      call.answer(<String, dynamic>{
        'mediaConstraints': <String, dynamic>{'audio': true, 'video': false},
      });
    } catch (error) {
      debugPrint('[CALLS] answerFromNotification failed: $error');
    }
  }

  Future<void> declineFromNotification(String callId) async {
    final callInfo = state.calls[callId];
    if (callInfo == null || callInfo.status == CallStatus.ended) {
      return;
    }
    try {
      await _engine.hangup(callId);
    } catch (error) {
      debugPrint('[CALLS] declineFromNotification failed: $error');
    }
  }

  @override
  CallState build() {
    _registerGlobalCallNotifierInstance(this);
    _engine = ref.read(sipEngineProvider);
    _eventSubscription = ref.listen<AsyncValue<SipEvent>>(
      sipEventsProvider,
      (previous, next) => next.whenData(_onEvent),
    );
    ref.listen<AsyncValue<AppLifecycleState>>(
      appLifecycleProvider,
      (previous, next) => next.whenData((state) {
        if (state == AppLifecycleState.resumed) {
          debugPrint('[INCOMING] app lifecycle resumed, checking hint');
          unawaited(handleIncomingCallHintIfAny());
        }
      }),
    );
    ref.onDispose(() {
      _eventSubscription?.close();
      _disposeWatchdog();
      _cancelRegistrationErrorTimer();
      unawaited(_releaseAudioFocus());
      _unregisterGlobalCallNotifierInstance(this);
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
        _handleRegistrationFailure(event.message ?? 'SIP registration failed');
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

    final now = DateTime.now();
    _recentlyEnded.removeWhere(
      (_, ts) => now.difference(ts) > _recentlyEndedTtl,
    );
    if (_recentlyEnded.containsKey(callId)) {
      debugPrint(
        '[SIP] ignoring late ${event.type.name} for ended callId=$callId active=${state.activeCallId}',
      );
      return;
    }

    final activeId = state.activeCallId;
    final pendingId = _pendingCallId;
    final activeCall = state.activeCall;
    final hasActive =
        activeCall != null && activeCall.status != CallStatus.ended;
    final pendingInfo = pendingId != null ? state.calls[pendingId] : null;
    final isPendingKnown =
        pendingId != null &&
        (state.calls.containsKey(pendingId) || _dialTimeoutCallId == pendingId);
    final stitchingCandidate =
        event.type == SipEventType.ringing &&
        pendingId != null &&
        callId != pendingId &&
        callId != activeId &&
        isPendingKnown &&
        (pendingInfo == null ||
            now.difference(pendingInfo.createdAt) <=
                const Duration(seconds: 10));
    if (stitchingCandidate && !state.calls.containsKey(callId)) {
      debugPrint(
        '[SIP] allowing ringing as stitching candidate callId=$callId pending=$pendingId active=$activeId',
      );
    }
    final callIdUnknown =
        !state.calls.containsKey(callId) &&
        callId != activeId &&
        (pendingId == null || callId != pendingId);
    if (event.type == SipEventType.ringing &&
        callIdUnknown &&
        _busyUntil != null &&
        now.isBefore(_busyUntil!) &&
        !stitchingCandidate) {
      final canReject =
          _lastStrayRingingRejectAt == null ||
          now.difference(_lastStrayRingingRejectAt!) >
              _strayRingingRejectMinGap;
      if (canReject) {
        _lastStrayRingingRejectAt = now;
        _rejectBusyCall(callId, event.type);
        return;
      }
    }
    final allowed =
        !hasActive ||
        callId == activeId ||
        (pendingId != null && (callId == pendingId || activeId == pendingId)) ||
        stitchingCandidate;

    if (!allowed) {
      if (event.type == SipEventType.ringing && isBusy) {
        _rejectBusyCall(callId, event.type);
        return;
      }
      debugPrint(
        '[INCOMING] ignoring stray ${event.type.name} callId=$callId active=$activeId pending=$pendingId',
      );
      return;
    }

    final status = _mapStatus(event.type);
    if (status == CallStatus.connected) {
      unawaited(_ensureAudioFocus(callId));
    } else if (status == CallStatus.ended) {
      unawaited(_releaseAudioFocus());
    }
    final pendingCallId = _pendingCallId;
    final previous =
        state.calls[callId] ??
        (pendingCallId != null ? state.calls[pendingCallId] : null);
    final destination = previous?.destination ?? event.message ?? 'call';
    final logs = List<String>.from(previous?.timeline ?? [])
      ..add(_describe(event));
    final originDongleId =
        _callDongleMap[callId] ??
        (pendingCallId != null ? _callDongleMap[pendingCallId] : null);

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
      dongleId: originDongleId,
    );
    if (pendingCallId != null && pendingCallId != callId) {
      updated.remove(pendingCallId);
    }
    if (originDongleId != null) {
      _callDongleMap[callId] = originDongleId;
    }
    if (pendingCallId != null && pendingCallId != callId) {
      _callDongleMap.remove(pendingCallId);
    }

    var activeCallId = state.activeCallId;
    if (status == CallStatus.ended) {
      _recentlyEnded[callId] = now;
      if (pendingCallId != null && pendingCallId != callId) {
        _recentlyEnded[pendingCallId] = now;
      }
      if (activeCallId == callId || activeCallId == pendingCallId) {
        activeCallId = null;
      }
      _cancelDialTimeout();
      _pendingCallId = null;
      _callDongleMap.remove(callId);
      if (pendingCallId != null) {
        _callDongleMap.remove(pendingCallId);
      }
      _busyUntil = now.add(_busyGrace);
    } else {
      _busyUntil = null;
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

  void _rejectBusyCall(String callId, SipEventType type) {
    final now = DateTime.now();
    _busyRejected.removeWhere((_, ts) => now.difference(ts) > _busyRejectTtl);
    if (_busyRejected.containsKey(callId)) {
      debugPrint(
        '[INCOMING] already rejected callId=$callId, skipping duplicate (event=${type.name})',
      );
      return;
    }
    _busyRejected[callId] = now;
    final active = state.activeCall;
    final activeInfo = active != null
        ? '${active.id}/${active.status.name}'
        : '<none>';
    debugPrint(
      '[INCOMING] busy rejecting callId=$callId event=${type.name} active=$activeInfo (fallback hangup)',
    );
    unawaited(_engine.hangup(callId));
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
      _setError(_pendingRegistrationError ?? 'SIP registration failed');
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
      _setError('Call was not answered, ending');
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
      errorMessage: 'Network is unstable',
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
      _setError('Network is unstable, ending call');
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
        (state.errorMessage == 'Network is unstable' ||
            state.errorMessage == 'Network is unstable, ending call')) {
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
