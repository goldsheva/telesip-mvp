import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

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
import 'package:app/services/network_connectivity_service.dart';
import 'package:app/sip/sip_engine.dart';
import 'package:app/features/auth/state/auth_notifier.dart';
import 'package:app/features/auth/state/auth_state.dart';

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
  bool _disposed = false;
  final NetworkConnectivityService _connectivityService =
      NetworkConnectivityService();
  bool _connectivityListenerActive = false;
  StreamSubscription<bool>? _connectivitySubscription;
  DateTime? _lastOnlineHandledAt;
  bool _lastKnownOnline = false;
  static const Duration _connectivityDebounce = Duration(seconds: 2);
  DateTime? _lastSipRegisteredAt;
  DateTime? _lastNetworkActivityAt;
  DateTime? _healthStartedAt;
  DateTime? _bootstrapCompletedAt;
  Timer? _reconnectTimer;
  bool _reconnectInFlight = false;
  int _reconnectBackoffIndex = 0;
  Timer? _healthCheckTimer;
  bool _isRegistered = false;
  AuthStatus? _lastAuthStatus;
  bool _authListenerActive = false;
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
  bool _bootstrapInFlight = false;
  bool _hintForegroundGuard = false;
  DateTime? _lastAudioRouteRefresh;
  bool _audioRouteRefreshInFlight = false;
  static const Duration _sipHealthTimeout = Duration(seconds: 20);
  static const Duration _healthCheckInterval = Duration(seconds: 10);
  static const Duration _maxBackoff = Duration(seconds: 30);
  static const List<Duration> _backoffDelays = [
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 4),
    Duration(seconds: 8),
    Duration(seconds: 16),
    _maxBackoff,
  ];
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
  final Map<String, DateTime> _processedPendingCallActions = {};
  static const Duration _pendingCallActionDedupTtl = Duration(seconds: 120);

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
    final engineCallId = _resolveEngineCallId(callId);
    if (engineCallId == null) {
      debugPrint('[CALLS] hangup ignored: no active engine call for $callId');
      await _endCallAndCleanup(callId, reason: 'user-hangup');
      return;
    }
    await _engine.hangup(engineCallId);
    await _endCallAndCleanup(callId, reason: 'user-hangup');
  }

  Future<void> sendDtmf(String callId, String digits) async {
    if (digits.isEmpty) return;
    final targetCallId = _resolveEngineCallId(callId);
    if (targetCallId == null) {
      debugPrint('[CALLS] sendDtmf ignored: call $callId not active');
      return;
    }
    await _engine.sendDtmf(targetCallId, digits);
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
    final requiresNotificationClear =
        cancelNotification || clearPendingHint || clearPendingAction;
    String? pairedSipId;
    if (callIdIsSip) {
      pairedSipId = callId;
    } else {
      for (final entry in _sipToLocalCallId.entries) {
        if (entry.value == localId) {
          pairedSipId = entry.key;
          break;
        }
      }
    }
    final calls = previousState.calls;
    final hasEntry =
        calls.containsKey(callId) ||
        (localId != callId && calls.containsKey(localId));
    final activeOrPending = activeMatches || pendingMatches;
    if (!hasEntry && !activeOrPending && !requiresNotificationClear) {
      _recentlyEnded[callId] = now;
      if (localId != callId) {
        _recentlyEnded[localId] = now;
      }
      if (markRecentlyEndedForSipPair && pairedSipId != null) {
        _recentlyEnded[pairedSipId] = now;
      }
      debugPrint(
        '[CALLS] endCall no-op reason=$reason callId=$callId localId=$localId paired=$pairedSipId',
      );
      return;
    }
    var clearedHint = false;
    var clearedAction = false;
    if (requiresNotificationClear) {
      final cleanupResult = await _clearCallNotificationState(
        callId,
        cancelNotification: cancelNotification,
        clearPendingHint: clearPendingHint,
        clearPendingAction: clearPendingAction,
      );
      clearedHint = cleanupResult.clearedHint;
      clearedAction = cleanupResult.clearedAction;
    }
    if (!relevant) {
      debugPrint(
        '[CALLS] endCall reason=$reason callId=$callId localId=$localId relevant=false skipping cleanup',
      );
      return;
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
    final endedInState =
        callInfo != null && callInfo.status != CallStatus.ended;
    final removedKeys = <String>[];
    if (updatedCalls.containsKey(callInfoKey)) {
      updatedCalls.remove(callInfoKey);
      removedKeys.add(callInfoKey);
    }
    final secondaryKey = callIdIsSip ? localId : pairedSipId;
    if (secondaryKey != null && secondaryKey != callInfoKey) {
      if (updatedCalls.containsKey(secondaryKey)) {
        updatedCalls.remove(secondaryKey);
        removedKeys.add(secondaryKey);
      }
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

    if (nextActiveCallId != null &&
        !updatedCalls.containsKey(nextActiveCallId)) {
      debugPrint(
        '[CALLS] clearing dangling activeCallId=$nextActiveCallId reason=$reason',
      );
      nextActiveCallId = null;
    }
    final nextState = previousState.copyWith(
      calls: updatedCalls,
      activeCallId: nextActiveCallId,
    );
    _commit(nextState);
    if (removedKeys.isNotEmpty) {
      debugPrint(
        '[CALLS] removed ended call(s) from state calls: keys=$removedKeys',
      );
    }
    debugPrint(
      '[CALLS] endCall reason=$reason callId=$callId localId=$localId '
      'activeWas=$activeWas endedKey=$callInfoKey endedInState=$endedInState '
      'clearedActive=$clearedActive clearedHint=$clearedHint clearedAction=$clearedAction '
      'relevant=true',
    );
  }

  Future<_CallNotificationCleanupResult> _clearCallNotificationState(
    String callId, {
    bool cancelNotification = false,
    bool clearPendingHint = false,
    bool clearPendingAction = false,
  }) async {
    var clearedAction = false;
    var clearedHint = false;
    if (cancelNotification) {
      if (kDebugMode) {
        debugPrint(
          '[CALLS_NOTIF] cleanup order update->cancel->clear callId=$callId',
        );
      }
      final ids = _notificationCallIds(callId);
      if (kDebugMode) {
        debugPrint('[CALLS_NOTIF] cancelIncoming ids=$ids');
      }
      await _maybeUpdateNotificationToNotRinging(callId);
      await _cancelIncomingNotificationsForCall(callId);
    }
    if (clearPendingAction) {
      try {
        final pendingAction =
            await IncomingNotificationService.readCallAction();
        final actionCallId =
            pendingAction?['call_id']?.toString() ??
            pendingAction?['callId']?.toString();
        if (_callIdMatches(callId, actionCallId)) {
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
        if (_callIdMatches(callId, pendingCallId) ||
            _callIdMatches(callId, pendingCallUuid)) {
          await FcmStorage.clearPendingIncomingHint();
          clearedHint = true;
        }
      } catch (_) {
        // best-effort
      }
    }
    return _CallNotificationCleanupResult(
      clearedAction: clearedAction,
      clearedHint: clearedHint,
    );
  }

  bool _callIdMatches(String referenceCallId, String? candidate) {
    if (candidate == null) return false;
    final localId = _sipToLocalCallId.containsKey(referenceCallId)
        ? _sipToLocalCallId[referenceCallId]!
        : referenceCallId;
    if (candidate == referenceCallId || candidate == localId) {
      return true;
    }
    for (final entry in _sipToLocalCallId.entries) {
      if (entry.value == localId && candidate == entry.key) {
        return true;
      }
      if (entry.key == referenceCallId && candidate == entry.value) {
        return true;
      }
    }
    return false;
  }

  Future<void> _cancelIncomingNotificationsForCall(String callId) async {
    final ids = _notificationCallIds(callId);
    for (final id in ids) {
      try {
        final callUuid = id == callId ? null : id;
        await IncomingNotificationService.cancelIncoming(
          callId: callId,
          callUuid: callUuid,
        );
      } catch (_) {
        // best-effort
      }
    }
  }

  Set<String> _notificationCallIds(String callId) {
    final ids = <String>{};
    ids.add(callId);
    final localId = _sipToLocalCallId.containsKey(callId)
        ? _sipToLocalCallId[callId]!
        : callId;
    ids.add(localId);
    final sipId = _sipIdForLocal(localId);
    if (sipId != null) {
      ids.add(sipId);
    }
    return ids;
  }

  String? _sipIdForLocal(String localId) {
    for (final entry in _sipToLocalCallId.entries) {
      if (entry.value == localId) {
        return entry.key;
      }
    }
    return null;
  }

  CallInfo? _callInfoForNotification(String callId) {
    final baseInfo = state.calls[callId];
    if (baseInfo != null) return baseInfo;
    final localId = _sipToLocalCallId.containsKey(callId)
        ? _sipToLocalCallId[callId]!
        : callId;
    final localInfo = state.calls[localId];
    if (localInfo != null) return localInfo;
    final sipId = _sipIdForLocal(localId);
    if (sipId != null) {
      return state.calls[sipId];
    }
    return null;
  }

  Future<void> _maybeUpdateNotificationToNotRinging(String callId) async {
    final info = _callInfoForNotification(callId);
    if (info == null) return;
    String? payloadFrom;
    String? payloadDisplayName;
    String? payloadCallId;
    String? payloadCallUuid;
    try {
      final pending = await FcmStorage.readPendingIncomingHint();
      final payload = pending == null
          ? null
          : pending['payload'] as Map<String, dynamic>?;
      if (payload == null) return;
      final rawFrom = payload['from'];
      if (rawFrom == null) return;
      payloadFrom = rawFrom.toString().trim();
      final rawDisplay = payload['display_name'];
      if (rawDisplay != null) {
        payloadDisplayName = rawDisplay.toString().trim();
      }
      final rawCallId = payload['call_id'];
      if (rawCallId != null) {
        payloadCallId = rawCallId.toString();
      }
      final rawCallUuid = payload['call_uuid'];
      if (rawCallUuid != null) {
        payloadCallUuid = rawCallUuid.toString();
      }
    } catch (_) {
      // best-effort
    }
    if (payloadFrom == null || payloadFrom.isEmpty) return;
    final matchesCallId =
        payloadCallId != null &&
        payloadCallId.isNotEmpty &&
        _callIdMatches(callId, payloadCallId);
    final matchesCallUuid =
        payloadCallUuid != null &&
        payloadCallUuid.isNotEmpty &&
        _callIdMatches(callId, payloadCallUuid);
    if (!matchesCallId && !matchesCallUuid) {
      return;
    }
    String? callUuid;
    if (matchesCallUuid) {
      callUuid = payloadCallUuid;
    } else if (matchesCallId && payloadCallUuid?.isNotEmpty == true) {
      callUuid = payloadCallUuid;
    }
    final normalizedDisplay = (payloadDisplayName?.isNotEmpty == true
        ? payloadDisplayName
        : null);
    if (kDebugMode) {
      debugPrint(
        '[CALLS_NOTIF] updateNotRinging callId=$callId callUuid=${callUuid ?? '<none>'} '
        'from=$payloadFrom display=${normalizedDisplay ?? '<none>'}',
      );
    }
    try {
      await IncomingNotificationService.updateIncomingState(
        callId: callId,
        from: payloadFrom,
        displayName: normalizedDisplay,
        callUuid: callUuid,
        isRinging: false,
      );
    } catch (_) {
      // best-effort
    }
  }

  bool get _incomingRegistrationReady =>
      state.isRegistered ||
      (_isRegistered &&
          _lastRegistrationState == SipRegistrationState.registered);

  bool get _hasActiveCall =>
      state.activeCall != null && state.activeCall!.status != CallStatus.ended;

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

  bool _isCallAlive(String id) {
    final snapshot = state;
    final calls = snapshot.calls;
    final activeId = snapshot.activeCallId;
    final localId = _sipToLocalCallId.containsKey(id)
        ? _sipToLocalCallId[id]!
        : id;
    String? sipId;
    if (_sipToLocalCallId.containsKey(id)) {
      sipId = id;
    } else {
      for (final entry in _sipToLocalCallId.entries) {
        if (entry.value == localId) {
          sipId = entry.key;
          break;
        }
      }
    }
    bool checkId(String? candidate) {
      if (candidate == null) return false;
      final info = calls[candidate];
      return info != null && info.status != CallStatus.ended;
    }

    if (checkId(localId) || checkId(id) || checkId(sipId)) {
      return true;
    }
    if (activeId != null &&
        (activeId == id || activeId == localId || activeId == sipId)) {
      return checkId(activeId);
    }
    return false;
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

    if (!_isCallAlive(callId)) {
      debugPrint('[CALLS] setCallMuted ignored: call $callId not active');
      return false;
    }

    final targetCallId = _resolveEngineCallId(callId);
    if (targetCallId == null) {
      debugPrint('[CALLS] setCallMuted ignored: call $callId not active');
      return false;
    }

    final call = _engine.getCall(targetCallId);
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
    if (kDebugMode) {
      final engineCallId = _resolveEngineCallId(callId);
      debugPrint(
        '[CALLS_NOTIF] answerFromNotification callId=$callId engine=${engineCallId ?? '<unknown>'} '
        'active=${state.activeCallId ?? '<none>'} pending=${_pendingCallId ?? '<none>'}',
      );
    }
    await _answerIncomingCall(callId, source: 'answerFromNotification');
  }

  Future<void> declineFromNotification(String callId) async {
    if (kDebugMode) {
      final engineCallId = _resolveEngineCallId(callId);
      debugPrint(
        '[CALLS_NOTIF] declineFromNotification callId=$callId engine=${engineCallId ?? '<unknown>'} '
        'active=${state.activeCallId ?? '<none>'} pending=${_pendingCallId ?? '<none>'}',
      );
    }
    await _declineIncomingCall(callId, source: 'declineFromNotification');
  }

  Future<void> _answerIncomingCall(
    String callId, {
    required String source,
  }) async {
    await _clearCallNotificationState(
      callId,
      cancelNotification: true,
      clearPendingAction: true,
    );
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
    _busyUntil = DateTime.now().add(_busyGrace);
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
      await _clearCallNotificationState(
        callId,
        cancelNotification: true,
        clearPendingHint: true,
        clearPendingAction: true,
      );
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
      await _clearCallNotificationState(
        callId,
        cancelNotification: true,
        clearPendingHint: true,
        clearPendingAction: true,
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
      await _endCallAndCleanup(
        targetCallId,
        reason: 'decline',
        cancelNotification: true,
        clearPendingHint: true,
        clearPendingAction: true,
      );
    } catch (error) {
      debugPrint('[CALLS] $source failed: $error');
    }
  }

  String? _resolveEngineCallId(String requestedId) {
    final localId = _sipToLocalCallId.containsKey(requestedId)
        ? _sipToLocalCallId[requestedId]!
        : requestedId;
    String? sipId;
    if (_sipToLocalCallId.containsKey(requestedId)) {
      sipId = requestedId;
    } else {
      for (final entry in _sipToLocalCallId.entries) {
        if (entry.value == localId) {
          sipId = entry.key;
          break;
        }
      }
    }
    final candidates = <String?>[
      requestedId,
      localId,
      sipId,
      state.activeCallId,
      _pendingCallId,
      _pendingLocalCallId,
    ];
    for (final candidate in candidates) {
      if (candidate == null) {
        continue;
      }
      if (_engine.getCall(candidate) != null) {
        return candidate;
      }
    }
    final activeId = state.activeCallId;
    debugPrint(
      '[CALLS] resolveEngineCallId failed for $requestedId active=$activeId pending=$_pendingCallId pendingLocal=$_pendingLocalCallId',
    );
    return null;
  }

  @override
  CallState build() {
    _registerGlobalCallNotifierInstance(this);
    _engine = ref.read(sipEngineProvider);
    final initialStatus =
        ref.read(authNotifierProvider).value?.status ?? AuthStatus.unknown;
    _lastAuthStatus ??= initialStatus;
    if (!_authListenerActive) {
      _authListenerActive = true;
      ref.listen<AsyncValue<AuthState>>(authNotifierProvider, (previous, next) {
        final currentStatus = next.value?.status ?? AuthStatus.unknown;
        final previousStatus = _lastAuthStatus ?? AuthStatus.unknown;
        if (currentStatus == previousStatus) return;
        _lastAuthStatus = currentStatus;
        if (currentStatus == AuthStatus.authenticated &&
            previousStatus != AuthStatus.authenticated) {
          debugPrint(
            '[CALLS_CONN] auth authenticated -> ensureBootstrapped reason=auth-authenticated',
          );
          ensureBootstrapped('auth-authenticated');
          _maybeStartHealthWatchdog();
          debugDumpConnectivityAndSipHealth('auth-authenticated');
        }
      });
    }
    if (!_connectivityListenerActive) {
      _connectivityListenerActive = true;
      _connectivitySubscription = _connectivityService.onOnlineChanged.listen(
        _handleConnectivityChanged,
      );
      unawaited(
        _connectivityService.isOnline().then((online) {
          _lastKnownOnline = online;
          logConnectivitySnapshot('connectivity-init');
          if (online) {
            debugPrint(
              '[CALLS_CONN] net online (init) -> ensureBootstrapped reason=net-online-init',
            );
            ensureBootstrapped('net-online-init');
            _maybeStartHealthWatchdog();
          }
          debugDumpConnectivityAndSipHealth('connectivity-init');
        }),
      );
    }
    unawaited(_ensureStoredIncomingCredentialsLoaded());
    _eventSubscription = ref.listen<AsyncValue<SipEvent>>(
      sipEventsProvider,
      (previous, next) => next.whenData((event) {
        if (_disposed) return;
        final previousChain = _eventChain;
        final nextChain = previousChain.then((_) async {
          if (_disposed) return;
          await _onEvent(event);
        });
        late final Future<void> completion;
        final handledChain = nextChain
            .catchError((error, stack) {
              debugPrint(
                '[CALLS] event processing failed: $error (sipEvent=${event.type.name})',
              );
              if (kDebugMode) {
                debugPrint(stack.toString());
              }
            })
            .whenComplete(() {
              if (_eventChain == completion && !_disposed) {
                _eventChain = Future<void>.value();
              }
            });
        completion = handledChain;
        _eventChain = handledChain;
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
      _disposed = true;
      _eventSubscription?.close();
      _connectivitySubscription?.cancel();
      _reconnectTimer?.cancel();
      _healthCheckTimer?.cancel();
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
    if (kDebugMode && _bootstrapDone) {
      debugPrint('[CALLS] bootstrapIfNeeded skip already done');
      return;
    }
    if (kDebugMode) {
      debugPrint(
        '[CALLS] bootstrapIfNeeded enter scheduled=$_bootstrapScheduled done=$_bootstrapDone '
        'active=${snapshot.activeCallId} status=${snapshot.activeCall?.status}',
      );
    }
    if (_bootstrapDone) return;
    if (_bootstrapInFlight) {
      if (kDebugMode) {
        debugPrint('[CALLS] bootstrapIfNeeded skip already in-flight');
      }
      return;
    }
    _bootstrapInFlight = true;
    try {
      final skipReason = _bootstrapPrerequisitesSkipReason();
      if (skipReason != null) {
        debugPrint('[CALLS] bootstrapIfNeeded skip: $skipReason');
        return;
      }
      _bootstrapDone = true;
      _bootstrapCompletedAt = DateTime.now();
      _syncForegroundServiceState(snapshot);
      unawaited(handleIncomingCallHintIfAny());
      _maybeStartHealthWatchdog();
    } finally {
      _bootstrapInFlight = false;
    }
  }

  void ensureBootstrapped(String reason) {
    if (kDebugMode) {
      final status =
          state.errorMessage ??
          state.activeCall?.status.toString() ??
          'no-call';
      debugPrint(
        '[CALLS] ensureBootstrapped reason=$reason scheduled=$_bootstrapScheduled done=$_bootstrapDone stateActive=${state.activeCallId} status=$status',
      );
    }
    if (_bootstrapDone) return;
    if (_bootstrapInFlight) {
      if (kDebugMode) {
        debugPrint(
          '[CALLS] ensureBootstrapped skip: bootstrap already in-flight',
        );
      }
      return;
    }
    if (!_bootstrapScheduled) {
      _bootstrapScheduled = true;
      final snapshot = state;
      Future.microtask(() => _bootstrapIfNeeded(snapshot));
      return;
    }
    _bootstrapIfNeeded(state);
  }

  String? _bootstrapPrerequisitesSkipReason() {
    final authState = ref.read(authNotifierProvider);
    final authStatus = authState.value?.status ?? AuthStatus.unknown;
    if (authStatus != AuthStatus.authenticated) {
      return 'authStatus=${authStatus.name}';
    }
    if (!_lastKnownOnline) {
      return 'offline';
    }
    return null;
  }

  void _handleConnectivityChanged(bool online) {
    final now = DateTime.now();
    if (!online) {
      debugPrint('[CALLS_CONN] net offline');
      _lastKnownOnline = false;
      _lastOnlineHandledAt = null;
      _reconnectTimer?.cancel();
      _reconnectTimer = null;
      _reconnectInFlight = false;
      _stopHealthWatchdog();
      debugDumpConnectivityAndSipHealth('net-offline');
      return;
    }
    final lastHandled = _lastOnlineHandledAt;
    if (lastHandled != null &&
        now.difference(lastHandled) < _connectivityDebounce) {
      debugPrint('[CALLS_CONN] net online skip (debounce)');
      return;
    }
    _lastKnownOnline = true;
    _lastOnlineHandledAt = now;

    final activeCall = state.activeCall;
    if (_hasActiveCall) {
      debugPrint(
        '[CALLS_CONN] net online skip activeCallId=${state.activeCallId ?? '<none>'} '
        'status=${activeCall?.status ?? '<none>'}',
      );
      return;
    }

    logConnectivitySnapshot('net-online');
    debugPrint(
      '[CALLS_CONN] net online -> ensureBootstrapped reason=net-online',
    );
    ensureBootstrapped('net-online');
    _maybeStartHealthWatchdog();
    if (!_isRegistered && !state.isRegistered) {
      _scheduleReconnect('net-online');
    }
    debugDumpConnectivityAndSipHealth('net-online');
  }

  void logConnectivitySnapshot(String tag) {
    if (!kDebugMode) return;
    final AuthStatus authStatus =
        ref.read(authNotifierProvider).value?.status ?? AuthStatus.unknown;
    final activeCall = state.activeCall;
    final lastNetAge = _lastNetworkActivityAt == null
        ? '<none>'
        : '${DateTime.now().difference(_lastNetworkActivityAt!).inSeconds}s';
    debugPrint(
      '[CALLS_CONN] $tag authStatus=${authStatus.name} online=$_lastKnownOnline '
      'scheduled=$_bootstrapScheduled done=$_bootstrapDone inFlight=$_bootstrapInFlight '
      'active=${state.activeCallId ?? '<none>'} '
      'status=${activeCall?.status ?? '<none>'} '
      'lastNetAge=$lastNetAge backoffIndex=$_reconnectBackoffIndex '
      'registeredAt=${_lastSipRegisteredAt != null}',
    );
  }

  void debugDumpConnectivityAndSipHealth(String tag) {
    if (!kDebugMode) return;
    final AuthStatus authStatus =
        ref.read(authNotifierProvider).value?.status ?? AuthStatus.unknown;
    final activeCall = state.activeCall;
    final lastNetAge = _lastNetworkActivityAt == null
        ? '<none>'
        : '${DateTime.now().difference(_lastNetworkActivityAt!).inSeconds}s';
    final healthTimerActive = _healthCheckTimer != null;
    final reconnectTimerActive = _reconnectTimer != null;
    debugPrint(
      '[CALLS_CONN] $tag authStatus=${authStatus.name} online=$_lastKnownOnline '
      'scheduled=$_bootstrapScheduled done=$_bootstrapDone inFlight=$_bootstrapInFlight '
      'registered=$_isRegistered stateRegistered=${state.isRegistered} '
      'lastRegistrationState=${_lastRegistrationState.name} '
      'lastNetAge=$lastNetAge healthTimer=$healthTimerActive '
      'reconnectTimer=$reconnectTimerActive reconnectInFlight=$_reconnectInFlight '
      'backoffIndex=$_reconnectBackoffIndex '
      'active=${state.activeCallId ?? '<none>'} status=${activeCall?.status ?? '<none>'}',
    );
  }

  void _maybeStartHealthWatchdog() {
    if (_disposed) return;
    final AuthStatus authStatus =
        ref.read(authNotifierProvider).value?.status ?? AuthStatus.unknown;
    if (!_lastKnownOnline || authStatus != AuthStatus.authenticated) {
      _stopHealthWatchdog();
      return;
    }
    if (_healthCheckTimer != null) return;
    _healthStartedAt = DateTime.now();
    _healthCheckTimer = Timer.periodic(_healthCheckInterval, _checkSipHealth);
  }

  void _stopHealthWatchdog() {
    _healthCheckTimer?.cancel();
    _healthCheckTimer = null;
    _healthStartedAt = null;
  }

  void _checkSipHealth(Timer timer) {
    if (!_lastKnownOnline) return;
    if (_hasActiveCall) return;
    final AuthStatus authStatus =
        ref.read(authNotifierProvider).value?.status ?? AuthStatus.unknown;
    if (authStatus != AuthStatus.authenticated) return;
    final now = DateTime.now();
    final activityAt = _lastNetworkActivityAt;
    if (activityAt == null) {
      final start = _healthStartedAt ?? _bootstrapCompletedAt;
      if (start != null && now.difference(start) > _sipHealthTimeout) {
        _scheduleReconnect('no-network-activity');
      }
      return;
    }
    if (now.difference(activityAt) > _sipHealthTimeout) {
      _scheduleReconnect('health-timeout');
    }
  }

  void _scheduleReconnect(String reason) {
    if (_disposed) return;
    final AuthStatus authStatus =
        ref.read(authNotifierProvider).value?.status ?? AuthStatus.unknown;
    if (authStatus != AuthStatus.authenticated) {
      debugPrint(
        '[CALLS_CONN] scheduleReconnect skip reason=$reason authStatus=${authStatus.name}',
      );
      return;
    }
    if (!_lastKnownOnline) {
      debugPrint(
        '[CALLS_CONN] scheduleReconnect skip reason=$reason online=false',
      );
      return;
    }
    if (_hasActiveCall) {
      debugPrint(
        '[CALLS_CONN] scheduleReconnect skip reason=$reason activeCallId=${state.activeCallId ?? '<none>'}',
      );
      return;
    }
    if (_reconnectInFlight) {
      debugPrint(
        '[CALLS_CONN] scheduleReconnect skip reason=$reason inFlight=true',
      );
      return;
    }
    _reconnectTimer?.cancel();
    final idx = math.min(_reconnectBackoffIndex, _backoffDelays.length - 1);
    final delay = _backoffDelays[idx];
    final attemptNumber = idx + 1;
    final lastNetAge = _lastNetworkActivityAt == null
        ? '<none>'
        : '${DateTime.now().difference(_lastNetworkActivityAt!).inSeconds}s';
    debugPrint(
      '[CALLS_CONN] scheduleReconnect reason=$reason attempt=$attemptNumber '
      'delayMs=${delay.inMilliseconds} online=$_lastKnownOnline '
      'authStatus=${authStatus.name} registered=$_isRegistered '
      'lastNetAge=$lastNetAge backoffIndex=$_reconnectBackoffIndex',
    );
    debugDumpConnectivityAndSipHealth('scheduleReconnect');
    _reconnectTimer = Timer(delay, () => _performReconnect(reason));
    _reconnectBackoffIndex = math.min(
      _reconnectBackoffIndex + 1,
      _backoffDelays.length - 1,
    );
  }

  Future<void> _performReconnect(String reason) async {
    if (_disposed) return;
    _reconnectTimer = null;
    if (_reconnectInFlight) return;
    if (!_lastKnownOnline) {
      debugPrint('[CALLS_CONN] reconnect skip reason=$reason online=false');
      return;
    }
    if (_hasActiveCall) {
      debugPrint(
        '[CALLS_CONN] reconnect skip reason=$reason activeCallId=${state.activeCallId ?? '<none>'}',
      );
      return;
    }
    final AuthStatus authStatus =
        ref.read(authNotifierProvider).value?.status ?? AuthStatus.unknown;
    if (authStatus != AuthStatus.authenticated) {
      debugPrint(
        '[CALLS_CONN] reconnect skip reason=$reason authStatus=${authStatus.name}',
      );
      return;
    }
    final reconnectUser = _lastKnownUser ?? _incomingUser;
    if (reconnectUser == null) {
      debugPrint('[CALLS_CONN] reconnect skip reason=$reason missing_user');
      return;
    }
    _reconnectInFlight = true;
    try {
      debugPrint('[CALLS_CONN] reconnect fired reason=$reason');
      await ensureRegistered(reconnectUser);
    } catch (error) {
      debugPrint('[CALLS_CONN] reconnect failed: $error');
    } finally {
      _reconnectInFlight = false;
    }
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
    final now = DateTime.now();
    if (event.type == SipEventType.registration) {
      final registrationState = event.registrationState;
      if (registrationState != null) {
        _lastNetworkActivityAt = now;
        if (registrationState == SipRegistrationState.registered) {
          _lastSipRegisteredAt = now;
          _reconnectBackoffIndex = 0;
        }
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
        final stateName = registrationState?.name ?? 'unknown';
        _scheduleReconnect('registration-$stateName');
      } else if (registrationState == SipRegistrationState.unregistered ||
          registrationState == SipRegistrationState.none) {
        _isRegistered = false;
        _registeredUserId = null;
        if (registrationState == SipRegistrationState.unregistered) {
          final stateName = registrationState?.name ?? 'unknown';
          _scheduleReconnect('registration-$stateName');
        }
      }
      _commit(state.copyWith(isRegistered: _isRegistered));
      return;
    }
    final sipCallId = event.callId;
    if (sipCallId == null) return;

    final effectiveId = _sipToLocalCallId[sipCallId] ?? sipCallId;
    var callId = effectiveId;
    final localId = _sipToLocalCallId.containsKey(callId)
        ? _sipToLocalCallId[callId]!
        : callId;

    final status = _mapStatus(event.type);
    _recentlyEnded.removeWhere(
      (_, ts) => now.difference(ts) > _recentlyEndedTtl,
    );
    if (_recentlyEnded.containsKey(callId) ||
        _recentlyEnded.containsKey(sipCallId)) {
      debugPrint(
        '[CALLS] ignoring late sip event event=${event.type.name} sipId=$sipCallId effectiveId=$callId (recently ended)',
      );
      return;
    }
    final allowAlive =
        status == CallStatus.dialing || status == CallStatus.ringing;
    if (!allowAlive && !_isCallAlive(callId) && !_isCallAlive(sipCallId)) {
      debugPrint(
        '[CALLS] ignoring event for dead call event=${event.type.name} sipId=$sipCallId effectiveId=$callId localId=$localId dead=true',
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
    if (previous == null &&
        status != CallStatus.dialing &&
        status != CallStatus.ringing) {
      debugPrint(
        '[CALLS] ignoring late non-dialing/ringing event=${event.type.name} sipId=$sipCallId effectiveId=$callId localId=${_sipToLocalCallId.containsKey(callId) ? _sipToLocalCallId[callId] : callId}',
      );
      return;
    }
    final destination = previous?.destination ?? event.message ?? 'call';
    final logs = List<String>.from(previous?.timeline ?? [])
      ..add(_describe(event));
    final originDongleId =
        _callDongleMap[callId] ??
        (pendingCallId != null ? _callDongleMap[pendingCallId] : null);

    final updated = Map<String, CallInfo>.from(state.calls);
    if (status != CallStatus.ended) {
      updated[callId] = CallInfo(
        id: callId,
        destination: destination,
        status: status,
        createdAt: previous?.createdAt ?? event.timestamp,
        connectedAt: status == CallStatus.connected
            ? event.timestamp
            : previous?.connectedAt,
        endedAt: previous?.endedAt,
        timeline: logs,
        dongleId: originDongleId,
      );
    }
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
      await _endCallAndCleanup(callId, reason: _endReasonForEvent(event.type));
      final postCleanupState = state;
      final callCleared = postCleanupState.activeCallId == null;
      final endedPreviousActive = callId == previousState.activeCallId;
      final shouldResetAudio = callCleared || endedPreviousActive;
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
    if (!updated.containsKey(activeCallId)) {
      activeCallId = updated.containsKey(callId) ? callId : null;
      if (kDebugMode) {
        debugPrint(
          '[CALLS] corrected activeCallId -> $activeCallId (post-update)',
        );
      }
    }
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
    final now = DateTime.now();
    _processedPendingCallActions.removeWhere(
      (_, timestamp) => now.difference(timestamp) > _pendingCallActionDedupTtl,
    );
    var dedupSkipped = 0;
    var unknownCleared = 0;
    var processed = 0;
    for (final item in raw) {
      if (item is! Map) continue;
      final type = item['type']?.toString();
      final callId = item['callId']?.toString();
      if (type == null || callId == null) continue;
      final tsKey = item['ts']?.toString() ?? '';
      final dedupKey = '$type|$callId|$tsKey';
      if (_processedPendingCallActions.containsKey(dedupKey)) {
        debugPrint(
          '[CALLS] drainPendingCallActions skipping duplicate type=$type callId=$callId ts=$tsKey',
        );
        dedupSkipped++;
        continue;
      }
      _processedPendingCallActions[dedupKey] = now;
      if (type == 'answer') {
        processed++;
        if (!_isCallAlive(callId)) {
          debugPrint(
            '[CALLS] pending answer for unknown call $callId, clearing',
          );
          await _clearCallNotificationState(
            callId,
            cancelNotification: true,
            clearPendingAction: true,
            clearPendingHint: true,
          );
          unknownCleared++;
          continue;
        }
        await answerFromNotification(callId);
      } else if (type == 'decline') {
        processed++;
        if (!_isCallAlive(callId)) {
          debugPrint(
            '[CALLS] pending decline for unknown call $callId, clearing',
          );
          await _clearCallNotificationState(
            callId,
            cancelNotification: true,
            clearPendingAction: true,
            clearPendingHint: true,
          );
          unknownCleared++;
          continue;
        }
        await declineFromNotification(callId);
      }
    }
    if (kDebugMode) {
      final totalConsidered = processed + dedupSkipped;
      debugPrint(
        '[CALLS] drainPendingCallActions summary total=$totalConsidered '
        'processed=$processed dedupSkipped=$dedupSkipped unknownCleared=$unknownCleared',
      );
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

  String _endReasonForEvent(SipEventType type) {
    if (type == SipEventType.error) {
      return 'sip-error';
    }
    return 'sip-ended';
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
    final targetCallId = _resolveEngineCallId(callId);
    if (targetCallId == null) {
      debugPrint(
        '[INCOMING] busy reject skipped: no engine call for $callId (event=${type.name})',
      );
    } else {
      unawaited(_engine.hangup(targetCallId));
    }
    unawaited(
      _endCallAndCleanup(
        callId,
        reason: 'busy-reject',
        cancelNotification: true,
        clearPendingHint: true,
        clearPendingAction: true,
      ),
    );
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
      final engineCallId = _resolveEngineCallId(targetCallId);
      if (engineCallId != null) {
        await _engine.hangup(engineCallId);
      } else {
        debugPrint(
          '[CALLS] dial timeout hangup ignored: no engine call for $targetCallId',
        );
      }
      await _endCallAndCleanup(targetCallId, reason: 'dial-timeout');
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
    if (!_isCallAlive(callId)) {
      debugPrint('[CALLS] watchdog not attached: call $callId not active');
      return;
    }
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
      final engineCallId = _resolveEngineCallId(callId);
      if (engineCallId != null) {
        unawaited(_engine.hangup(engineCallId));
      } else {
        debugPrint(
          '[CALLS] watchdog hangup ignored: no engine call for $callId',
        );
      }
      unawaited(_endCallAndCleanup(callId, reason: 'watchdog-failure'));
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

class _CallNotificationCleanupResult {
  const _CallNotificationCleanupResult({
    required this.clearedAction,
    required this.clearedHint,
  });

  final bool clearedAction;
  final bool clearedHint;
}

final callControllerProvider = NotifierProvider<CallNotifier, CallState>(
  CallNotifier.new,
);
