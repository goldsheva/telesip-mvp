import 'dart:async';

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:app/config/env_config.dart';
import 'package:app/core/providers.dart';
import 'package:app/core/providers/sip_providers.dart';
import 'package:app/core/storage/fcm_storage.dart';
import 'package:app/core/storage/general_sip_credentials_storage.dart';
import 'package:app/core/storage/sip_auth_storage.dart';
import 'package:app/features/calls/call_watchdog.dart';
import 'package:app/features/dongles/models/dongle.dart';
import 'package:app/features/dongles/state/dongles_provider.dart';
import 'package:app/features/sip_users/models/pbx_sip_connection.dart';
import 'package:app/features/sip_users/models/pbx_sip_user.dart';
import 'package:app/platform/foreground_service.dart';
import 'package:app/services/audio_focus_service.dart';
import 'package:app/services/audio_route_service.dart';
import 'package:app/platform/system_settings.dart';
import 'package:app/services/permissions_service.dart';
import 'package:app/services/audio_route_types.dart';
import 'package:app/services/incoming_notification_service.dart';
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

Future<void> requestIncomingCallCancelProcessing(String callId) async {
  final handler = _globalCallNotifierInstance;
  if (handler == null) return;
  await handler.handleIncomingCallCancelled(callId);
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
    required this.isMuted,
    required this.audioRoute,
    required this.availableAudioRoutes,
  });

  factory CallState.initial() => CallState(
    calls: {},
    errorMessage: null,
    watchdogState: CallWatchdogState.ok(),
    isRegistered: false,
    isMuted: false,
    audioRoute: AudioRoute.systemDefault,
    availableAudioRoutes: const {AudioRoute.systemDefault},
  );

  final Map<String, CallInfo> calls;
  final String? activeCallId;
  final String? errorMessage;
  final CallWatchdogState watchdogState;
  final bool isRegistered;
  final bool isMuted;
  final AudioRoute audioRoute;
  final Set<AudioRoute> availableAudioRoutes;

  CallInfo? get activeCall => activeCallId != null ? calls[activeCallId] : null;

  List<CallInfo> get history =>
      calls.values.toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  CallState copyWith({
    Map<String, CallInfo>? calls,
    String? activeCallId,
    String? errorMessage,
    CallWatchdogState? watchdogState,
    bool? isRegistered,
    bool? isMuted,
    AudioRoute? audioRoute,
    Set<AudioRoute>? availableAudioRoutes,
  }) {
    return CallState(
      calls: calls ?? this.calls,
      activeCallId: activeCallId ?? this.activeCallId,
      errorMessage: errorMessage ?? this.errorMessage,
      watchdogState: watchdogState ?? this.watchdogState,
      isRegistered: isRegistered ?? this.isRegistered,
      isMuted: isMuted ?? this.isMuted,
      audioRoute: audioRoute ?? this.audioRoute,
      availableAudioRoutes: availableAudioRoutes ?? this.availableAudioRoutes,
    );
  }
}

enum _CallPhase { idle, ringing, connecting, active, ending }

const Duration _errorDedupTtl = Duration(seconds: 2);
const Set<AudioRoute> _defaultAvailableAudioRoutes = {AudioRoute.systemDefault};

class CallNotifier extends Notifier<CallState> {
  late final SipEngine _engine;
  ProviderSubscription<AsyncValue<SipEvent>>? _eventSubscription;
  Future<void> _eventChain = Future<void>.value();
  bool _isRegistered = false;
  String? _lastErrorMessage;
  DateTime? _lastErrorTimestamp;
  SipRegistrationState _lastRegistrationState = SipRegistrationState.none;
  int? _registeredUserId;
  PbxSipUser? _lastKnownUser;
  PbxSipUser? _incomingUser;
  PbxSipUser? _outgoingUser;
  GeneralSipCredentials? _storedIncomingCredentials;
  bool _storedIncomingCredentialsLoaded = false;
  Timer? _dialTimeoutTimer;
  String? _dialTimeoutCallId;
  CallWebRtcWatchdog? _webRtcWatchdog;
  String? _watchdogCallId;
  Timer? _watchdogFailureTimer;
  String? _failureTimerCallId;
  String? _pendingCallId;
  String? _pendingLocalCallId;
  final Map<String, String> _sipToLocalCallId = {};
  Timer? _registrationErrorTimer;
  String? _pendingRegistrationError;
  final Map<String, int?> _callDongleMap = {};
  bool _userInitiatedRetry = false;
  Timer? _retrySuppressionTimer;
  bool _watchdogErrorActive = false;
  bool _audioFocusHeld = false;
  String? _focusedCallId;
  bool _scoActive = false;
  _CallPhase _phase = _CallPhase.idle;
  bool _pendingActionsDrained = false;
  bool _foregroundRequested = false;
  bool _bootstrapDone = false;
  bool _bootstrapScheduled = false;
  bool _hintForegroundGuard = false;
  DateTime? _lastAudioRouteRefresh;
  bool _audioRouteRefreshInFlight = false;
  static const _notificationsChannel = MethodChannel('app.calls/notifications');
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
    if (activeCall != null && activeCall.status != CallStatus.ended) {
      const message = 'Cannot start a new call while one is active';
      _setError(message);
      debugPrint('[CALLS] startCall blocked: $message active=${activeCall.id}');
      return;
    }
    final trimmed = destination.trim();
    if (trimmed.isEmpty) return;
    if (_phase != _CallPhase.idle && _phase != _CallPhase.ending) {
      return;
    }
    await _ensureStoredIncomingCredentialsLoaded();
    final outgoingUser = _outgoingUser ?? _incomingUser;
    if (outgoingUser == null) {
      _setError('SIP is not registered');
      return;
    }
    try {
      await ensureRegistered(outgoingUser);
    } catch (_) {
      // Errors surface through notifier state; swallow here.
    }
    if (!_isRegistered) {
      _setError('SIP is not registered');
      return;
    }
    if (outgoingUser.dongleId == null) {
      debugPrint('[SIP] using GENERAL registration');
    } else {
      debugPrint(
        '[SIP] switching to DONGLE credentials for outgoing call: ${outgoingUser.dongleId}',
      );
    }
    _commit(
      state.copyWith(audioRoute: AudioRoute.earpiece, isMuted: false),
      syncFgs: false,
    );
    unawaited(_applyNativeAudioRoute(AudioRoute.earpiece));
    final prefixedDestination = _destinationWithBootstrapPrefix(
      trimmed,
      outgoingUser,
    );
    final callId = await _engine.startCall(prefixedDestination);
    _pendingCallId = callId;
    _pendingLocalCallId = callId;
    _callDongleMap[callId] = outgoingUser.dongleId;
    _startDialTimeout(callId);
    _clearError();
    _commit(state.copyWith(activeCallId: callId));
    _phase = _CallPhase.connecting;
  }

  Future<void> hangup(String callId) async {
    await _engine.hangup(callId);
  }

  Future<void> sendDtmf(String callId, String digits) async {
    if (digits.isEmpty) return;
    await _engine.sendDtmf(callId, digits);
  }

  Future<void> setIncomingSipUser(PbxSipUser user) async {
    // Remember the preferred incoming account while warming up registration.
    if (_incomingUser?.pbxSipUserId == user.pbxSipUserId) return;
    _incomingUser = user;
    try {
      await ensureRegistered(user);
    } catch (_) {
      // Errors surface through notifier state; swallow here.
    }
  }

  Future<void> setOutgoingSipUser(PbxSipUser user) async {
    // Hold the preferred outgoing account for deterministic registration.
    if (_outgoingUser?.pbxSipUserId == user.pbxSipUserId) return;
    _outgoingUser = user;
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
      _isRegistered = true;
      _lastRegistrationState = SipRegistrationState.registered;
      _registeredUserId = user.pbxSipUserId;
      _commit(state.copyWith(isRegistered: true));
    } catch (error) {
      if (_isRegistered) {
        _isRegistered = false;
        _commit(state.copyWith(isRegistered: false));
      }
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
      _isRegistered = true;
      _lastRegistrationState = SipRegistrationState.registered;
      _commit(state.copyWith(isRegistered: true));
      return true;
    } catch (error) {
      if (_isRegistered) {
        _isRegistered = false;
        _commit(state.copyWith(isRegistered: false));
      }
      _setError('SIP registration failed: $error');
      return false;
    }
  }

  Future<void> handleIncomingCallHintIfAny() async {
    await _ensureStoredIncomingCredentialsLoaded();
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

      _lastHintAttemptAt = now;
      final candidate =
          _incomingUser ??
          (_storedIncomingCredentials != null
              ? _incomingUserFromStoredCredentials(_storedIncomingCredentials!)
              : null);
      late final SipAuthSnapshot snapshot;
      if (candidate != null) {
        _incomingUser = candidate;
        final wsConnections = candidate.pbxSipConnections
            .where((c) => c.pbxSipProtocol.toLowerCase().contains('ws'))
            .toList();
        late final String wsUrl;
        String uriHost = '';
        if (wsConnections.isNotEmpty) {
          final connection = wsConnections.first;
          final protocol = connection.pbxSipProtocol.toLowerCase();
          final scheme = protocol.contains('wss')
              ? 'wss'
              : protocol.contains('ws')
              ? 'ws'
              : null;
          if (scheme == null) {
            debugPrint(
              '[INCOMING] unsupported SIP transport for incoming user, skipping hint (call_uuid=$callUuid)',
            );
            return;
          }
          wsUrl = '$scheme://${connection.pbxSipUrl}:${connection.pbxSipPort}/';
          uriHost = Uri.tryParse(wsUrl)?.host ?? connection.pbxSipUrl;
        } else {
          final defaultWs = EnvConfig.sipWebSocketUrl;
          if (defaultWs == null || defaultWs.isEmpty) {
            debugPrint(
              '[INCOMING] no WS endpoint configured for incoming user, skipping hint (call_uuid=$callUuid)',
            );
            return;
          }
          wsUrl = defaultWs;
          uriHost = Uri.tryParse(wsUrl)?.host ?? '';
        }
        if (uriHost.isEmpty) {
          debugPrint(
            '[INCOMING] invalid WS URL for incoming user, skipping hint (call_uuid=$callUuid)',
          );
          return;
        }
        snapshot = SipAuthSnapshot(
          uri: 'sip:${candidate.sipLogin}@$uriHost',
          password: candidate.sipPassword,
          wsUrl: wsUrl,
          displayName: candidate.sipLogin,
          timestamp: DateTime.now(),
        );
        debugPrint(
          '[INCOMING] registering SIP from stored incoming user (call_uuid=$callUuid)',
        );
      } else {
        final storedSnapshot = await ref
            .read(sipAuthStorageProvider)
            .readSnapshot();
        if (storedSnapshot == null) {
          debugPrint(
            '[INCOMING] no stored SIP credentials to register (call_uuid=$callUuid)',
          );
          return;
        }
        snapshot = storedSnapshot;
        debugPrint(
          '[INCOMING] registering SIP from hint (call_uuid=$callUuid)',
        );
      }
      bool registered = false;
      try {
        _startHintForegroundGuard();
        registered = await registerWithSnapshot(snapshot);
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
        _releaseHintForegroundGuard(registered: registered, sync: !registered);
      }
    } finally {
      _isHandlingHint = false;
    }
  }

  Future<void> handleIncomingCallCancelled(String callId) async {
    await _endCallAndCleanup(
      callId,
      reason: 'cancelled',
      cancelNotification: true,
      clearPendingHint: true,
      clearPendingAction: true,
    );
  }

  Future<void> _endCallAndCleanup(
    String callId, {
    required String reason,
    bool cancelNotification = false,
    bool clearPendingHint = false,
    bool clearPendingAction = false,
    bool markRecentlyEndedForSipPair = true,
  }) async {
    final now = DateTime.now();
    final callIdIsSip = _sipToLocalCallId.containsKey(callId);
    final localId = callIdIsSip ? _sipToLocalCallId[callId]! : callId;
    final previousState = state;
    final activeMatches =
        previousState.activeCallId != null &&
        (previousState.activeCallId == callId ||
            previousState.activeCallId == localId);
    final pendingMatches =
        (_pendingCallId != null &&
            (_pendingCallId == callId || _pendingCallId == localId)) ||
        (_pendingLocalCallId != null && _pendingLocalCallId == localId);
    final hasCallInfo =
        previousState.calls.containsKey(callId) ||
        (localId != callId && previousState.calls.containsKey(localId));
    final relevant =
        reason == 'cancelled' || activeMatches || pendingMatches || hasCallInfo;
    if (!relevant) {
      debugPrint(
        '[CALLS] endCall reason=$reason callId=$callId localId=$localId relevant=false skipping cleanup',
      );
      return;
    }

    String? pairedSipId;
    if (!callIdIsSip) {
      for (final entry in _sipToLocalCallId.entries) {
        if (entry.value == localId) {
          pairedSipId = entry.key;
          break;
        }
      }
    }

    bool matchesCallId(String? candidate) =>
        candidate != null && (candidate == callId || candidate == localId);
    var clearedHint = false;
    var clearedAction = false;

    if (cancelNotification) {
      try {
        await IncomingNotificationService.cancelIncoming(callId: callId);
      } catch (_) {
        // best-effort
      }
    }

    if (clearPendingAction) {
      try {
        final pendingAction =
            await IncomingNotificationService.readCallAction();
        final actionCallId =
            pendingAction?['call_id']?.toString() ??
            pendingAction?['callId']?.toString();
        if (matchesCallId(actionCallId)) {
          await IncomingNotificationService.clearCallAction();
          clearedAction = true;
        }
      } catch (_) {
        // best-effort
      }
    }

    if (clearPendingHint) {
      try {
        final pending = await FcmStorage.readPendingIncomingHint();
        final payload = pending?['payload'] as Map<String, dynamic>?;
        final pendingCallId = payload?['call_id']?.toString();
        final pendingCallUuid = payload?['call_uuid']?.toString();
        if (matchesCallId(pendingCallId) || matchesCallId(pendingCallUuid)) {
          await FcmStorage.clearPendingIncomingHint();
          clearedHint = true;
        }
      } catch (_) {
        // best-effort
      }
    }

    _recentlyEnded[callId] = now;
    if (localId != callId) {
      _recentlyEnded[localId] = now;
    }
    if (markRecentlyEndedForSipPair && pairedSipId != null) {
      _recentlyEnded[pairedSipId] = now;
    }

    var callInfoKey = callId;
    var callInfo = previousState.calls[callInfoKey];
    if (callInfo == null && localId != callId) {
      callInfoKey = localId;
      callInfo = previousState.calls[callInfoKey];
    }
    final updatedCalls = Map<String, CallInfo>.from(previousState.calls);
    var endedInState = false;
    if (callInfo != null && callInfo.status != CallStatus.ended) {
      final timeline = List<String>.from(callInfo.timeline)..add(reason);
      updatedCalls[callInfoKey] = callInfo.copyWith(
        status: CallStatus.ended,
        endedAt: now,
        timeline: timeline,
      );
      endedInState = true;
    }

    final activeWas = previousState.activeCallId;
    var nextActiveCallId = activeWas;
    var clearedActive = false;
    if (nextActiveCallId != null &&
        (nextActiveCallId == callId || nextActiveCallId == localId)) {
      nextActiveCallId = null;
      _busyUntil = now.add(_busyGrace);
      clearedActive = true;
    }

    _cancelDialTimeout();
    if (_pendingCallId == callId || _pendingCallId == localId) {
      _pendingCallId = null;
    }
    if (_pendingLocalCallId == localId) {
      _pendingLocalCallId = null;
    }
    _clearSipMappingsForLocalCall(localId);
    _callDongleMap.remove(localId);

    final nextState = previousState.copyWith(
      calls: updatedCalls,
      activeCallId: nextActiveCallId,
    );
    _commit(nextState);
    debugPrint(
      '[CALLS] endCall reason=$reason callId=$callId localId=$localId '
      'activeWas=$activeWas endedKey=$callInfoKey endedInState=$endedInState '
      'clearedActive=$clearedActive clearedHint=$clearedHint clearedAction=$clearedAction '
      'relevant=true',
    );
  }

  bool get _incomingRegistrationReady =>
      state.isRegistered ||
      (_isRegistered &&
          _lastRegistrationState == SipRegistrationState.registered);

  Future<bool> _ensureIncomingReady({
    Duration timeout = const Duration(seconds: 4),
  }) async {
    await handleIncomingCallHintIfAny();
    final deadline = DateTime.now().add(timeout);
    while (!_incomingRegistrationReady && DateTime.now().isBefore(deadline)) {
      await Future.delayed(const Duration(milliseconds: 200));
    }
    if (_incomingRegistrationReady) return true;
    debugPrint('[INCOMING] registration not ready after ${timeout.inSeconds}s');
    return false;
  }

  Future<bool> isBatteryOptimizationDisabled() async {
    if (!Platform.isAndroid) return true;
    return await SystemSettings.isIgnoringBatteryOptimizations();
  }

  Future<void> _ensureStoredIncomingCredentialsLoaded() async {
    if (_storedIncomingCredentialsLoaded) return;
    _storedIncomingCredentialsLoaded = true;
    final stored = await ref
        .read(generalSipCredentialsStorageProvider)
        .readCredentials();
    if (stored == null) return;
    _storedIncomingCredentials = stored;
    _incomingUser ??= _incomingUserFromStoredCredentials(stored);
  }

  PbxSipUser _incomingUserFromStoredCredentials(
    GeneralSipCredentials credentials,
  ) {
    return PbxSipUser(
      pbxSipUserId: credentials.sipUserId,
      userId: credentials.sipUserId,
      sipLogin: credentials.sipLogin,
      sipPassword: credentials.sipPassword,
      dialplanId: 0,
      dongleId: null,
      pbxSipConnections: const <PbxSipConnection>[],
    );
  }

  Future<void> _ensureAudioFocus(String callId) async {
    if (_phase == _CallPhase.idle || _phase == _CallPhase.ending) return;
    if (_audioFocusHeld && _focusedCallId == callId) return;
    try {
      await AudioFocusService.acquire(callId: callId);
      _audioFocusHeld = true;
      _focusedCallId = callId;
    } catch (error) {
      _audioFocusHeld = false;
      _focusedCallId = null;
    }
  }

  Future<void> _releaseAudioFocus() async {
    if (!_audioFocusHeld) return;
    try {
      await AudioFocusService.release();
    } catch (_) {
    } finally {
      _audioFocusHeld = false;
      _focusedCallId = null;
    }
  }

  Future<void> _maybeStartBluetoothSco() async {
    if (_scoActive) return;
    final info = await AudioRouteService.getRouteInfo();
    if (info?.current != AudioRoute.bluetooth) return;
    await AudioRouteService.startBluetoothSco();
    _scoActive = true;
  }

  Future<void> _maybeStopBluetoothSco() async {
    if (!_scoActive) return;
    await AudioRouteService.stopBluetoothSco();
    _scoActive = false;
  }

  Future<void> setCallAudioRoute(AudioRoute route) async {
    final activeCall = state.activeCall;
    if (state.activeCallId == null ||
        activeCall == null ||
        activeCall.status == CallStatus.ended ||
        (_phase != _CallPhase.connecting &&
            _phase != _CallPhase.active &&
            _phase != _CallPhase.ringing)) {
      debugPrint(
        '[CALLS] setCallAudioRoute ignored: no active call (phase=$_phase route=$route)',
      );
      return;
    }
    final available = state.availableAudioRoutes;
    final clampedRoute = _clampToAvailableRoute(route, available);
    if (!available.contains(route) && clampedRoute == state.audioRoute) {
      debugPrint(
        '[CALLS] setCallAudioRoute noop: requested=$route not available, staying on ${state.audioRoute}',
      );
      return;
    }
    if (clampedRoute != route) {
      debugPrint(
        '[CALLS] clamp audio route requested=$route -> $clampedRoute available=$available',
      );
    }
    if (clampedRoute == state.audioRoute) return;
    _commit(state.copyWith(audioRoute: clampedRoute), syncFgs: false);
    final availabilitySnapshot = state.availableAudioRoutes
        .map((route) => route.name)
        .join(',');
    debugPrint(
      '[CALLS] applying route requested=$route clamped=$clampedRoute available=$availabilitySnapshot',
    );
    unawaited(_applyNativeAudioRoute(clampedRoute));
    unawaited(_refreshAudioRoute());
  }

  AudioRoute _clampToAvailableRoute(
    AudioRoute requested,
    Set<AudioRoute> available,
  ) {
    if (available.contains(requested)) return requested;
    if (available.contains(AudioRoute.bluetooth)) return AudioRoute.bluetooth;
    if (available.contains(AudioRoute.earpiece)) return AudioRoute.earpiece;
    if (available.contains(AudioRoute.speaker)) return AudioRoute.speaker;
    return AudioRoute.systemDefault;
  }

  Future<bool> setCallMuted(bool muted) async {
    final callId = state.activeCallId ?? _pendingCallId;
    if (callId == null) return false;

    final call = _engine.getCall(callId);
    if (call == null) return false;

    if (state.isMuted == muted) return true;

    try {
      if (muted) {
        call.mute(true, false);
      } else {
        call.unmute(true, false);
      }
      _commit(state.copyWith(isMuted: muted), syncFgs: false);
      return true;
    } catch (error) {
      debugPrint('[CALLS] unable to toggle mute: $error');
      return false;
    }
  }

  Future<void> answer(String callId) async {
    await _answerIncomingCall(callId, source: 'answer');
  }

  Future<void> decline(String callId) async {
    await _declineIncomingCall(callId, source: 'decline');
  }

  Future<void> answerFromNotification(String callId) async {
    await _answerIncomingCall(callId, source: 'answerFromNotification');
  }

  Future<void> declineFromNotification(String callId) async {
    await _declineIncomingCall(callId, source: 'declineFromNotification');
  }

  Future<void> _answerIncomingCall(
    String callId, {
    required String source,
  }) async {
    final callInfo = state.calls[callId];
    if (callInfo != null && callInfo.status == CallStatus.ended) {
      return;
    }
    final ready = await _ensureIncomingReady();
    if (!ready) {
      debugPrint('[CALLS] $source aborted: registration not ready');
      return;
    }
    final micOk = await PermissionsService.ensureMicrophonePermission();
    if (!micOk) {
      debugPrint('[CALLS] $source aborted: microphone denied');
      return;
    }
    final engineCallId = _resolveEngineCallId(callId);
    if (engineCallId == null) {
      debugPrint(
        '[CALLS] $source unknown call $callId active=${state.activeCallId} '
        'pending=$_pendingCallId',
      );
      return;
    }
    if (engineCallId != callId) {
      debugPrint(
        '[CALLS] $source resolved callId requested=$callId engine=$engineCallId',
      );
    }
    final call = _engine.getCall(engineCallId);
    if (call == null) {
      debugPrint(
        '[CALLS] $source resolved call $engineCallId but engine call missing',
      );
      return;
    }
    try {
      call.answer(<String, dynamic>{
        'mediaConstraints': <String, dynamic>{'audio': true, 'video': false},
      });
    } catch (error) {
      debugPrint('[CALLS] $source failed: $error');
    }
  }

  Future<void> _declineIncomingCall(
    String callId, {
    required String source,
  }) async {
    final callInfo = state.calls[callId];
    if (callInfo != null && callInfo.status == CallStatus.ended) {
      return;
    }
    final ready = await _ensureIncomingReady();
    if (!ready) {
      debugPrint('[CALLS] $source aborted: registration not ready');
      return;
    }
    var targetCallId = callId;
    final engineCallId = _resolveEngineCallId(callId);
    if (engineCallId == null) {
      debugPrint(
        '[CALLS] $source unknown call $callId active=${state.activeCallId} '
        'pending=$_pendingCallId',
      );
      return;
    }
    if (engineCallId != callId) {
      debugPrint(
        '[CALLS] $source resolved callId requested=$callId engine=$engineCallId',
      );
    }
    targetCallId = engineCallId;
    try {
      await _engine.hangup(targetCallId);
    } catch (error) {
      debugPrint('[CALLS] $source failed: $error');
    }
  }

  String? _resolveEngineCallId(String requestedId) {
    if (_engine.getCall(requestedId) != null) {
      return requestedId;
    }
    final activeId = state.activeCallId;
    if (activeId != null && _engine.getCall(activeId) != null) {
      return activeId;
    }
    final pendingId = _pendingCallId;
    if (pendingId != null && _engine.getCall(pendingId) != null) {
      return pendingId;
    }
    for (final entry in _sipToLocalCallId.entries) {
      if (entry.value == requestedId && _engine.getCall(entry.key) != null) {
        return entry.key;
      }
    }
    return null;
  }

  @override
  CallState build() {
    _registerGlobalCallNotifierInstance(this);
    _engine = ref.read(sipEngineProvider);
    unawaited(_ensureStoredIncomingCredentialsLoaded());
    _eventSubscription = ref.listen<AsyncValue<SipEvent>>(
      sipEventsProvider,
      (previous, next) => next.whenData((event) {
        _eventChain = _eventChain.then((_) => _onEvent(event)).catchError((
          error,
          stack,
        ) {
          debugPrint(
            '[CALLS] event processing failed: $error (sipEvent=${event.type.name})',
          );
          if (kDebugMode) {
            debugPrint(stack.toString());
          }
        });
      }),
    );
    ref.listen<AsyncValue<AppLifecycleState>>(
      appLifecycleProvider,
      (previous, next) => next.whenData((state) {
        if (state == AppLifecycleState.resumed) {
          debugPrint('[INCOMING] app lifecycle resumed, checking hint');
          unawaited(handleIncomingCallHintIfAny());
          final active = this.state.activeCall;
          if (active != null && active.status != CallStatus.ended) {
            unawaited(_refreshAudioRoute());
          }
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
    if (!_bootstrapScheduled) {
      _bootstrapScheduled = true;
      final bootstrapSnapshot = CallState.initial();
      Future.microtask(() => _bootstrapIfNeeded(bootstrapSnapshot));
      if (!_pendingActionsDrained) {
        _pendingActionsDrained = true;
        Future.microtask(() => _drainPendingCallActions());
      }
      return bootstrapSnapshot;
    }
    if (!_pendingActionsDrained) {
      _pendingActionsDrained = true;
      unawaited(_drainPendingCallActions());
    }
    return CallState.initial();
  }

  void _bootstrapIfNeeded(CallState snapshot) {
    if (_bootstrapDone) return;
    _bootstrapDone = true;
    _syncForegroundServiceState(snapshot);
    unawaited(handleIncomingCallHintIfAny());
  }

  void _commit(CallState next, {bool syncFgs = true}) {
    final previousState = state;
    final previousActiveId = previousState.activeCallId;
    final nextActiveId = next.activeCallId;
    final callEnded = previousActiveId != null && nextActiveId == null;
    CallState commitState = next;
    AudioRoute? forcedRoute;

    if (callEnded) {
      commitState = commitState.copyWith(
        availableAudioRoutes: _defaultAvailableAudioRoutes,
      );
    }

    final nextActiveIsNew =
        nextActiveId != null &&
        nextActiveId != previousActiveId &&
        !previousState.calls.containsKey(nextActiveId);
    if (nextActiveIsNew) {
      final activeCall = next.calls[nextActiveId];
      final outgoingDialing =
          activeCall != null && activeCall.status == CallStatus.dialing;
      forcedRoute = outgoingDialing
          ? AudioRoute.earpiece
          : AudioRoute.systemDefault;
      commitState = commitState.copyWith(
        isMuted: false,
        audioRoute: forcedRoute,
        availableAudioRoutes: _defaultAvailableAudioRoutes,
      );
      final statusLabel = activeCall != null
          ? activeCall.status.toString().split('.').last
          : '<unknown>';
      debugPrint(
        '[CALLS] hard-reset prev=$previousActiveId next=$nextActiveId '
        'newCall=true route=$forcedRoute status=$statusLabel',
      );
    }

    state = commitState;
    if (syncFgs) {
      _syncForegroundServiceState(commitState);
    }

    final becameActive =
        nextActiveId != null && (previousActiveId == null || nextActiveIsNew);
    if (forcedRoute != null) {
      debugPrint('[CALLS] refreshAudioRoute on call activate id=$nextActiveId');
      unawaited(_applyNativeAudioRoute(forcedRoute));
      unawaited(_refreshAudioRoute());
    } else if (becameActive) {
      debugPrint('[CALLS] refreshAudioRoute on call activate id=$nextActiveId');
      unawaited(_refreshAudioRoute());
    }
  }

  Future<void> _onEvent(SipEvent event) async {
    if (event.type == SipEventType.registration) {
      final registrationState = event.registrationState;
      if (registrationState != null) {
        _lastRegistrationState = registrationState;
      }
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
      _commit(state.copyWith(isRegistered: _isRegistered));
      return;
    }
    final sipCallId = event.callId;
    if (sipCallId == null) return;

    final effectiveId = _sipToLocalCallId[sipCallId] ?? sipCallId;
    var callId = effectiveId;

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

    var activeId = state.activeCallId;
    var pendingId = _pendingCallId;
    var activeCall = state.activeCall;
    var hasActive = activeCall != null && activeCall.status != CallStatus.ended;
    final previousState = state;
    final activeLabel = activeId ?? '<none>';
    debugPrint(
      '[SIP] event=${event.type.name} sipId=$sipCallId effectiveId=$effectiveId active=$activeLabel',
    );
    var callIdUnknown =
        !state.calls.containsKey(callId) &&
        callId != activeId &&
        (pendingId == null || callId != pendingId);
    final isOutgoingEvent =
        event.type == SipEventType.dialing ||
        event.callState == SipCallState.dialing;
    if (callIdUnknown &&
        pendingId != null &&
        _pendingLocalCallId != null &&
        isOutgoingEvent &&
        !_sipToLocalCallId.containsKey(sipCallId)) {
      final localPendingId = _pendingLocalCallId!;
      debugPrint(
        '[CALLS] mapped sipCallId=$sipCallId -> localCallId=$localPendingId',
      );
      _sipToLocalCallId[sipCallId] = localPendingId;
      callId = localPendingId;
      pendingId = localPendingId;
      _pendingCallId = localPendingId;
      _pendingLocalCallId = null;
      callIdUnknown = false;
    }
    final shouldAdoptIncoming =
        event.type == SipEventType.ringing &&
        callIdUnknown &&
        !hasActive &&
        !isBusy;
    var didAdoptIncoming = false;
    if (shouldAdoptIncoming) {
      final alreadyCancelled =
          _recentlyEnded.containsKey(callId) ||
          _recentlyEnded.containsKey(sipCallId);
      if (alreadyCancelled) {
        debugPrint(
          '[INCOMING] suppress adopt for cancelled call sipId=$sipCallId effectiveId=$callId',
        );
      } else {
        final incomingCalls = Map<String, CallInfo>.from(state.calls);
        final existing = incomingCalls[callId];
        final shouldForceRinging =
            existing == null ||
            (existing.status != CallStatus.connected &&
                existing.status != CallStatus.ended);
        if (existing == null) {
          incomingCalls[callId] = CallInfo(
            id: callId,
            destination: 'Incoming',
            status: CallStatus.ringing,
            createdAt: now,
            dongleId: null,
          );
        } else if (shouldForceRinging) {
          incomingCalls[callId] = existing.copyWith(status: CallStatus.ringing);
        }
        final nextState = state.copyWith(
          calls: incomingCalls,
          activeCallId: callId,
        );
        _clearError();
        _commit(nextState, syncFgs: false);
        _pendingCallId = callId;
        pendingId = callId;
        _phase = _CallPhase.ringing;
        debugPrint(
          '[INCOMING] adopted -> active ringing callId=$callId sipId=$sipCallId',
        );
        activeId = nextState.activeCallId;
        activeCall = nextState.activeCall;
        hasActive = activeCall != null && activeCall.status != CallStatus.ended;
        callIdUnknown = false;
        didAdoptIncoming = true;
      }
    }
    if (!_isRelevantCall(callId, activeId)) {
      debugPrint(
        '[SIP] ignoring event for non-active callId=$callId active=$activeId pending=$pendingId reason=non-relevant',
      );
      return;
    }
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
        '[INCOMING] ignoring stray ${event.type.name} callId=$callId active=$activeId pending=$pendingId reason=not-allowed',
      );
      return;
    }

    final status = _mapStatus(event.type);
    if (!didAdoptIncoming && !_isPhaseEventAllowed(status)) {
      debugPrint(
        '[SIP] invalid phase ${_phase.name} for ${event.type.name} callId=$callId',
      );
      return;
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

    var activeCallId = previousState.activeCallId;
    if (status == CallStatus.ended) {
      await _endCallAndCleanup(callId, reason: _describe(event));
      final postCleanupState = state;
      final callCleared = postCleanupState.activeCallId == null;
      final endedPreviousActive = callId == previousState.activeCallId;
      final shouldResetAudio = callCleared || endedPreviousActive;
      _applyPhase(status, callId);
      _handleWatchdogActivation(previousState, postCleanupState);
      if (shouldResetAudio) {
        unawaited(_applyNativeAudioRoute(AudioRoute.systemDefault));
      }
      Future.microtask(() {
        unawaited(handleIncomingCallHintIfAny());
      });
      return;
    }

    _busyUntil = null;
    if (status != CallStatus.dialing) {
      _cancelDialTimeout();
    }
    activeCallId = callId;
    if (_dialTimeoutCallId != null) {
      _dialTimeoutCallId = callId;
    }
    if (pendingCallId != null && pendingCallId != callId) {
      _clearSipMappingsForLocalCall(pendingCallId);
      _pendingCallId = null;
      _pendingLocalCallId = null;
    }

    final errorMessage = event.type == SipEventType.error
        ? event.message ?? 'SIP error'
        : null;
    final baseNext = previousState.copyWith(
      calls: updated,
      activeCallId: activeCallId,
      errorMessage: errorMessage,
    );
    final prevActiveId = previousState.activeCallId;
    final nextActiveId = baseNext.activeCallId;
    final callCleared = nextActiveId == null;
    final endedPreviousActive =
        status == CallStatus.ended && callId == prevActiveId;
    final shouldResetAudio = callCleared || endedPreviousActive;
    final next = shouldResetAudio
        ? baseNext.copyWith(
            isMuted: false,
            audioRoute: AudioRoute.systemDefault,
          )
        : baseNext;
    _applyPhase(status, callId);
    _handleWatchdogActivation(previousState, next);
    _commit(next);
    if (shouldResetAudio) {
      unawaited(_applyNativeAudioRoute(AudioRoute.systemDefault));
    }
    if (status == CallStatus.connected ||
        status == CallStatus.ringing ||
        status == CallStatus.dialing) {
      unawaited(_refreshAudioRoute());
    }
  }

  _CallPhase _phaseForStatus(CallStatus status) {
    switch (status) {
      case CallStatus.dialing:
        return _CallPhase.connecting;
      case CallStatus.ringing:
        return _CallPhase.ringing;
      case CallStatus.connected:
        return _CallPhase.active;
      case CallStatus.ended:
        return _CallPhase.ending;
    }
  }

  void _applyPhase(CallStatus status, String callId) {
    final next = _phaseForStatus(status);
    if (next == _phase) return;
    _phase = next;
    if (next != _CallPhase.ringing && next != _CallPhase.connecting) {
      _cancelDialTimeout();
    }
    if (next == _CallPhase.ringing || next == _CallPhase.connecting) {
      unawaited(_ensureAudioFocus(callId));
    } else if (next == _CallPhase.active) {
      unawaited(_maybeStartBluetoothSco());
    } else if (next == _CallPhase.ending) {
      unawaited(_releaseAudioFocus());
      unawaited(_maybeStopBluetoothSco());
      Future.microtask(() {
        if (_phase == _CallPhase.ending) {
          _phase = _CallPhase.idle;
        }
      });
    }
  }

  void _syncForegroundServiceState(CallState s) {
    final hasActiveCall =
        s.activeCall != null && s.activeCall!.status != CallStatus.ended;
    final shouldRun = s.isRegistered || hasActiveCall;
    debugPrint(
      '[CALLS] sync foreground service (shouldRun=$shouldRun requested=$_foregroundRequested)',
    );
    if (shouldRun && !_foregroundRequested) {
      _foregroundRequested = true;
      unawaited(ForegroundService.startForegroundService());
    } else if (!shouldRun && _foregroundRequested) {
      _foregroundRequested = false;
      unawaited(ForegroundService.stopForegroundService());
    }
  }

  void _startHintForegroundGuard() {
    if (!Platform.isAndroid || _foregroundRequested || _hintForegroundGuard) {
      return;
    }
    debugPrint('[INCOMING] hint foreground guard start');
    _hintForegroundGuard = true;
    unawaited(ForegroundService.startForegroundService());
  }

  void _releaseHintForegroundGuard({
    required bool registered,
    bool sync = true,
  }) {
    if (!_hintForegroundGuard) return;
    _hintForegroundGuard = false;
    debugPrint(
      '[INCOMING] hint foreground guard release (registered=$registered)',
    );
    if (sync) {
      _syncForegroundServiceState(state);
    }
  }

  bool maybeSuggestBatteryOptimization() {
    if (!Platform.isAndroid) return false;
    return state.isRegistered ||
        (state.activeCall != null &&
            state.activeCall!.status != CallStatus.ended);
  }

  Future<void> _drainPendingCallActions() async {
    final ready = await _ensureIncomingReady();
    if (!ready) {
      debugPrint(
        '[CALLS] drainPendingCallActions aborted: registration not ready',
      );
      return;
    }
    final raw = await _notificationsChannel.invokeMethod<List<dynamic>>(
      'drainPendingCallActions',
    );
    if (raw == null || raw.isEmpty) return;
    for (final item in raw) {
      if (item is! Map) continue;
      final type = item['type']?.toString();
      final callId = item['callId']?.toString();
      if (type == null || callId == null) continue;
      if (type == 'answer') {
        await answerFromNotification(callId);
      } else if (type == 'decline') {
        await hangup(callId);
      }
    }
  }

  bool _isPhaseEventAllowed(CallStatus status) {
    return switch (_phase) {
      _CallPhase.idle =>
        status == CallStatus.ringing || status == CallStatus.dialing,
      _CallPhase.ringing =>
        status == CallStatus.connected || status == CallStatus.ended,
      _CallPhase.connecting =>
        status == CallStatus.connected || status == CallStatus.ended,
      _CallPhase.active =>
        status == CallStatus.connected || status == CallStatus.ended,
      _CallPhase.ending => status == CallStatus.ended,
    };
  }

  bool _isRelevantCall(String callId, String? activeId) {
    return callId == activeId ||
        (_pendingCallId != null && callId == _pendingCallId);
  }

  void _clearSipMappingsForLocalCall(String localCallId) {
    final keysToRemove = _sipToLocalCallId.entries
        .where((entry) => entry.value == localCallId)
        .map((entry) => entry.key)
        .toList();
    for (final key in keysToRemove) {
      _sipToLocalCallId.remove(key);
    }
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
    final now = DateTime.now();
    if (_lastErrorMessage == message &&
        _lastErrorTimestamp != null &&
        now.difference(_lastErrorTimestamp!) < _errorDedupTtl) {
      return;
    }
    _lastErrorMessage = message;
    _lastErrorTimestamp = now;
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
      final activeId = state.activeCallId;
      final pendingId = _pendingCallId;
      if (targetCallId != activeId && targetCallId != pendingId) return;
      final callInfo = state.calls[targetCallId];
      if (callInfo?.status == CallStatus.ended) return;
      if (_phase != _CallPhase.connecting && _phase != _CallPhase.ringing) {
        return;
      }
      _setError('Call timed out, ending');
      await _engine.hangup(targetCallId);
      _cancelDialTimeout();
    });
  }

  void _cancelDialTimeout() {
    _dialTimeoutTimer?.cancel();
    _dialTimeoutTimer = null;
    _dialTimeoutCallId = null;
  }

  Future<void> _refreshAudioRoute() async {
    final now = DateTime.now();
    if (_audioRouteRefreshInFlight) return;
    if (_lastAudioRouteRefresh != null &&
        now.difference(_lastAudioRouteRefresh!) <
            const Duration(milliseconds: 500)) {
      return;
    }
    final active = state.activeCall;
    if (active == null || active.status == CallStatus.ended) {
      return;
    }
    _audioRouteRefreshInFlight = true;
    _lastAudioRouteRefresh = now;
    try {
      final info = await AudioRouteService.getRouteInfo();
      if (info == null) return;
      final availableRoutes = Set<AudioRoute>.from(info.available)
        ..add(AudioRoute.systemDefault);
      AudioRoute desiredRoute = info.current;
      if (!availableRoutes.contains(desiredRoute)) {
        if (availableRoutes.contains(AudioRoute.bluetooth)) {
          desiredRoute = AudioRoute.bluetooth;
        } else if (availableRoutes.contains(AudioRoute.earpiece)) {
          desiredRoute = AudioRoute.earpiece;
        } else if (availableRoutes.contains(AudioRoute.speaker)) {
          desiredRoute = AudioRoute.speaker;
        } else {
          desiredRoute = AudioRoute.systemDefault;
        }
        debugPrint(
          '[CALLS] refreshAudioRoute fallback: nativeCurrentMissing native=${info.current} -> desired=$desiredRoute',
        );
      }
      final availableChanged = !setEquals(
        availableRoutes,
        state.availableAudioRoutes,
      );
      final shouldLog = desiredRoute != state.audioRoute || availableChanged;
      if (shouldLog) {
        final availableNames =
            availableRoutes.map((route) => route.name).toList()..sort();
        debugPrint(
          '[CALLS] refreshAudioRoute native=${info.current} desired=$desiredRoute '
          'available=${availableNames.join(',')} commit=$shouldLog',
        );
      }
      if (desiredRoute != state.audioRoute || availableChanged) {
        _commit(
          state.copyWith(
            audioRoute: desiredRoute,
            availableAudioRoutes: availableRoutes,
          ),
          syncFgs: false,
        );
      }
    } catch (error) {
      debugPrint('[CALLS] refreshAudioRoute failed: $error');
    } finally {
      _audioRouteRefreshInFlight = false;
    }
  }

  Future<void> _applyNativeAudioRoute(AudioRoute route) async {
    try {
      await AudioRouteService.setRoute(route);
    } catch (error) {
      debugPrint('[CALLS] applyAudioRoute($route) failed: $error');
    }
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

  String _destinationWithBootstrapPrefix(String destination, PbxSipUser user) {
    final prefix = _bootstrapPrefixForUser(user);
    if (prefix == null || prefix.isEmpty) return destination.trim();
    final trimmed = destination.trim();
    if (trimmed.isEmpty) return trimmed;
    if (_destinationAlreadyHasPrefix(trimmed, prefix)) {
      return trimmed;
    }
    const encodedSeparator = '%23';
    final candidate = '$prefix$encodedSeparator$trimmed';
    return candidate;
  }

  bool _destinationAlreadyHasPrefix(String destination, String prefix) {
    var candidate = destination.trim();
    if (candidate.isEmpty) return false;
    if (candidate.toLowerCase().startsWith('sip:')) {
      candidate = candidate.substring(4);
    }
    final atIndex = candidate.indexOf('@');
    if (atIndex >= 0) {
      candidate = candidate.substring(0, atIndex);
    }
    if (candidate.startsWith('+')) {
      candidate = candidate.substring(1);
    }
    candidate = candidate.replaceAll('%23', '#');
    return candidate.startsWith('$prefix#');
  }

  String? _bootstrapPrefixForUser(PbxSipUser user) {
    final dongleId = user.dongleId;
    if (dongleId == null) return null;
    final dongles = ref
        .read(donglesProvider)
        .maybeWhen(data: (List<Dongle> data) => data, orElse: () => null);
    if (dongles == null) return null;
    for (final dongle in dongles) {
      if (dongle.dongleId == dongleId) {
        final prefix = dongle.bootstrapPbxSipUser?.trim();
        if (prefix != null && prefix.isNotEmpty) {
          return prefix;
        }
        break;
      }
    }
    return null;
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
