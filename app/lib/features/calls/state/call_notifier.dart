import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:app/config/env_config.dart';
import 'package:app/core/providers.dart';
import 'package:app/core/providers/sip_providers.dart';
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

import 'call_models.dart';
import 'call_sip_registration_handler.dart';
import 'call_notification_cleanup.dart';
import 'call_incoming_hint_handler.dart';
import 'call_connectivity_listener.dart';
import 'call_reconnect_helpers.dart';
import 'call_reconnect_scheduler.dart';
import 'call_reconnect_service.dart';
import 'call_health_watchdog.dart';
import 'call_bootstrap_service.dart';
import 'call_auth_listener.dart';
import 'call_sip_health_policy.dart';
import 'call_reconnect_executor.dart';
import 'call_sip_snapshot_builder.dart';
import 'call_connectivity_debug_dumper.dart';

export 'call_models.dart';
export 'call_incoming_hint_handler.dart';

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

enum _CallPhase { idle, ringing, connecting, active, ending }

const Duration _errorDedupTtl = Duration(seconds: 2);
const Set<AudioRoute> _defaultAvailableAudioRoutes = {AudioRoute.systemDefault};

class CallNotifier extends Notifier<CallState> {
  late final SipEngine _engine;
  ProviderSubscription<AsyncValue<SipEvent>>? _eventSubscription;
  Future<void> _eventChain = Future<void>.value();
  bool _disposed = false;
  bool get _alive => !_disposed;
  final NetworkConnectivityService _connectivityService =
      NetworkConnectivityService();
  DateTime? _lastOnlineHandledAt;
  bool _lastKnownOnline = false;
  static const Duration _connectivityDebounce = Duration(seconds: 2);
  DateTime? _lastSipRegisteredAt;
  DateTime? _lastNetworkActivityAt;
  DateTime? _healthStartedAt;
  DateTime? _bootstrapCompletedAt;
  bool _reconnectInFlight = false;
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
  final Map<String, Timer> _endedCleanupTimers = {};
  bool _userInitiatedRetry = false;
  Timer? _retrySuppressionTimer;
  bool _watchdogErrorActive = false;
  bool _audioFocusHeld = false;
  String? _focusedCallId;
  bool _scoActive = false;
  _CallPhase _phase = _CallPhase.idle;
  int _startCallSeq = 0;
  bool _pendingActionsDrained = false;
  bool _foregroundRequested = false;
  bool _bootstrapDone = false;
  bool _bootstrapScheduled = false;
  late final CallNotificationCleanup _notifCleanup;
  late final CallIncomingHintHandler _incomingHintHandler;
  late final CallConnectivityListener _connectivityListener;
  late final CallReconnectScheduler _reconnectScheduler;
  late final CallHealthWatchdog _healthWatchdog;
  late final CallReconnectExecutor _reconnectExecutor;
  late final CallSipRegistrationHandler _registrationHandler;
  final CallConnectivityDebugDumper _debugDumper =
      const CallConnectivityDebugDumper();
  final CallReconnectService _reconnectService = const CallReconnectService();
  final CallBootstrapService _bootstrapService = const CallBootstrapService();
  late final CallAuthListener _authListener = CallAuthListener(
    isDisposed: () => _disposed,
  );
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
  static const Duration _dialTimeout = Duration(seconds: 25);
  static const Duration _endedCleanupDelay = Duration(milliseconds: 800);
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

  bool get isBusy {
    final baseBusy =
        state.activeCall != null &&
        state.activeCall!.status != CallStatus.ended;
    final graceBusy =
        _busyUntil != null && DateTime.now().isBefore(_busyUntil!);
    return baseBusy || graceBusy;
  }

  Future<void> startCall(String destination) async {
    final trimmed = destination.trim();
    final seq = ++_startCallSeq;
    final logContext =
        'phase=$_phase active=${state.activeCallId} calls=${state.calls.length} '
        'pendingSip=$_pendingCallId pendingLocal=$_pendingLocalCallId '
        'dialTimeoutId=${_dialTimeoutCallId ?? "<none>"} dialTimer=${_dialTimeoutTimer != null} '
        'bootstrapDone=$_bootstrapDone scheduled=$_bootstrapScheduled';
    debugPrint('[CALLS] startCall enter seq=$seq number=$trimmed $logContext');
    if (trimmed.isEmpty) {
      debugPrint(
        '[CALLS] startCall skip reason=empty-number number=$trimmed $logContext',
      );
      return;
    }
    _resetDialLocksIfIdle(state, 'startCall-precheck');
    final snap = _sanitizeActiveCallId(state, 'startCall-precheck');
    if (!identical(snap, state)) {
      _commitSafe(snap);
    }
    if (!_isDialPhaseAllowed()) {
      debugPrint(
        '[CALLS] startCall skip reason=phase-not-idle seq=$seq $logContext',
      );
      return;
    }
    if (_isBusyForDial(snap)) {
      final activeCall = snap.activeCall;
      if (activeCall != null && activeCall.status != CallStatus.ended) {
        const message = 'Cannot start a new call while one is active';
        _setError(message);
        debugPrint(
          '[CALLS] startCall skip reason=active-existing number=$trimmed '
          '$logContext active=${activeCall.id} status=${activeCall.status}',
        );
      } else {
        debugPrint('[CALLS] startCall skip reason=busy seq=$seq $logContext');
      }
      return;
    }
    await _ensureStoredIncomingCredentialsLoaded();
    final outgoingUser = _outgoingUser ?? _incomingUser;
    if (outgoingUser == null) {
      _setError('SIP is not registered');
      debugPrint(
        '[CALLS] startCall skip reason=no-outgoing-user number=$trimmed $logContext',
      );
      return;
    }
    try {
      await ensureRegistered(outgoingUser);
    } catch (_) {
      // Errors surface through notifier state; swallow here.
    }
    if (!_isRegistered) {
      _setError('SIP is not registered');
      debugPrint(
        '[CALLS] startCall skip reason=not-registered number=$trimmed '
        '$logContext isRegistered=$_isRegistered',
      );
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
    final updatedCalls = Map<String, CallInfo>.from(state.calls)
      ..[callId] = CallInfo(
        id: callId,
        destination: prefixedDestination,
        status: CallStatus.dialing,
        createdAt: DateTime.now(),
        dongleId: outgoingUser.dongleId,
      );
    _commit(state.copyWith(calls: updatedCalls, activeCallId: callId));
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
    _incomingUser = user;
    if (!_isRegistered || _registeredUserId != user.pbxSipUserId) {
      try {
        await ensureRegistered(user);
      } catch (_) {
        // Errors surface through notifier state; swallow here.
      }
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

    final snapshot = _snapshotForUser(user);
    if (snapshot == null) return;
    try {
      _clearError();
      await _engine.register(
        uri: snapshot.uri,
        password: snapshot.password,
        wsUrl: snapshot.wsUrl,
        displayName: snapshot.displayName,
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

  SipAuthSnapshot? _snapshotForUser(PbxSipUser user) {
    final result = buildSipSnapshot(
      connections: user.sipConnections,
      sipLogin: user.sipLogin,
      sipPassword: user.sipPassword,
      defaultWsUrl: EnvConfig.sipWebSocketUrl,
      treatEmptyDefaultAsMissing: false,
      setError: _setError,
    );
    return result.snapshot;
  }

  Future<void> handleIncomingCallHintIfAny() {
    return _incomingHintHandler.handleIncomingCallHintIfAny();
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
    if (_disposed) return;
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
      final cleanupResult = await _notifCleanup.clearCallNotificationState(
        callId,
        cancelNotification: cancelNotification,
        clearPendingHint: clearPendingHint,
        clearPendingAction: clearPendingAction,
      );
      if (_disposed) return;
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
    final callStatus = callInfo?.status;
    final wasLive = callStatus != null && callStatus != CallStatus.ended;
    final removedKeys = <String>[];
    final secondaryKey = callIdIsSip ? localId : pairedSipId;
    final shouldDelayCleanup =
        wasLive &&
        _wasEarlyPhase(callStatus) &&
        _shouldGraceDelayForReason(reason);
    if (updatedCalls.containsKey(callInfoKey)) {
      if (shouldDelayCleanup) {
        final endedCall = callInfo!;
        final endedCallUpdated = endedCall.copyWith(
          status: CallStatus.ended,
          endedAt: now,
        );
        updatedCalls[callInfoKey] = endedCallUpdated;
        if (secondaryKey != null && secondaryKey != callInfoKey) {
          final secondaryCall = updatedCalls[secondaryKey];
          if (secondaryCall != null) {
            updatedCalls[secondaryKey] = secondaryCall.copyWith(
              status: CallStatus.ended,
              endedAt: now,
            );
          }
        }
        _scheduleEndedCleanup(
          primaryId: callInfoKey,
          secondaryId: secondaryKey,
          endedAt: now,
          reason: reason,
        );
      } else {
        updatedCalls.remove(callInfoKey);
        removedKeys.add(callInfoKey);
      }
    }
    if (secondaryKey != null &&
        secondaryKey != callInfoKey &&
        updatedCalls.containsKey(secondaryKey) &&
        !shouldDelayCleanup) {
      updatedCalls.remove(secondaryKey);
      removedKeys.add(secondaryKey);
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
    if (!_hasLiveCalls(updatedCalls.values)) {
      _pendingCallId = null;
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
    if (nextActiveCallId == null) {
      for (final entry in updatedCalls.entries) {
        if (entry.value.status != CallStatus.ended) {
          nextActiveCallId = entry.key;
          break;
        }
      }
    }
    final nextState = previousState.copyWith(
      calls: updatedCalls,
      activeCallId: nextActiveCallId,
    );
    final post = _sanitizeActiveCallId(nextState, 'endCall-postcommit');
    _commitSafe(post);
    scheduleMicrotask(() {
      if (!_alive) return;
      _resetDialLocksIfIdle(post, 'endCall-postcommit');
    });
    debugPrint(
      '[CALLS] endCall final active=${post.activeCallId} calls=${post.calls.length}',
    );
    if (removedKeys.isNotEmpty) {
      debugPrint(
        '[CALLS] removed ended call(s) from state calls: keys=$removedKeys',
      );
    }
    debugPrint(
      '[CALLS] endCall reason=$reason callId=$callId localId=$localId '
      'activeWas=$activeWas endedKey=$callInfoKey endedInState=$wasLive '
      'clearedActive=$clearedActive clearedHint=$clearedHint clearedAction=$clearedAction '
      'relevant=true',
    );
  }

  bool get _incomingRegistrationReady =>
      state.isRegistered ||
      (_isRegistered &&
          _lastRegistrationState == SipRegistrationState.registered);

  bool get _hasActiveCall =>
      state.activeCall != null && state.activeCall!.status != CallStatus.ended;

  Future<bool> _ensureIncomingReady({
    Duration timeout = const Duration(seconds: 4),
  }) {
    return _bootstrapService.ensureIncomingReady(
      isDisposed: () => _disposed,
      handleIncomingCallHint: handleIncomingCallHintIfAny,
      incomingRegistrationReady: () => _incomingRegistrationReady,
      log: debugPrint,
      timeout: timeout,
    );
  }

  Future<bool> isBatteryOptimizationDisabled() async {
    if (!Platform.isAndroid) return true;
    return await SystemSettings.isIgnoringBatteryOptimizations();
  }

  Future<void> _ensureStoredIncomingCredentialsLoaded() async {
    if (_disposed) return;
    if (_storedIncomingCredentialsLoaded) return;
    _storedIncomingCredentialsLoaded = true;
    final stored = await ref
        .read(generalSipCredentialsStorageProvider)
        .readCredentials();
    if (_disposed) return;
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
    await _notifCleanup.clearCallNotificationState(
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
      await _notifCleanup.clearCallNotificationState(
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
      await _notifCleanup.clearCallNotificationState(
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
    _notifCleanup = CallNotificationCleanup(
      getState: () => state,
      sipToLocalCallId: _sipToLocalCallId,
    );
    _incomingHintHandler = CallIncomingHintHandler(
      isDisposed: () => _disposed,
      ensureStoredIncomingCredentialsLoaded:
          _ensureStoredIncomingCredentialsLoaded,
      registerWithSnapshot: registerWithSnapshot,
      getIncomingUser: () => _incomingUser,
      setIncomingUser: (user) => _incomingUser = user,
      getStoredIncomingCredentials: () => _storedIncomingCredentials,
      incomingUserFromStoredCredentials: _incomingUserFromStoredCredentials,
      readStoredSnapshot: () => ref.read(sipAuthStorageProvider).readSnapshot(),
      startHintForegroundGuard: _startHintForegroundGuard,
      releaseHintForegroundGuard: _releaseHintForegroundGuard,
      isBusy: () => isBusy,
      log: (message) => debugPrint(message),
    );
    _reconnectScheduler = CallReconnectScheduler(
      isDisposed: () => _disposed,
      backoffDelays: _backoffDelays,
    );
    _healthWatchdog = CallHealthWatchdog(
      isDisposed: () => _disposed,
      interval: _healthCheckInterval,
      onTick: _checkSipHealthTick,
    );
    _reconnectExecutor = CallReconnectExecutor(
      isDisposed: () => _disposed,
      log: (message) => debugPrint(message),
    );
    _registrationHandler = CallSipRegistrationHandler(
      setLastNetworkActivityAt: (value) => _lastNetworkActivityAt = value,
      setLastSipRegisteredAt: (value) => _lastSipRegisteredAt = value,
      resetReconnectBackoff: () => _reconnectScheduler.resetBackoff(),
      hasReconnectTimer: () => _reconnectScheduler.hasScheduledTimer,
      isReconnectInFlight: () => _reconnectInFlight,
      setReconnectInFlight: (value) => _reconnectInFlight = value,
      cancelReconnect: () => _reconnectScheduler.cancel(),
      stopHealthWatchdog: _stopHealthWatchdog,
      setLastRegistrationState: (state) => _lastRegistrationState = state,
      setIsRegistered: (value) => _isRegistered = value,
      getIsRegistered: () => _isRegistered,
      setRegisteredUserId: (value) => _registeredUserId = value,
      getLastKnownUserId: () => _lastKnownUser?.pbxSipUserId,
      cancelRegistrationErrorTimer: _cancelRegistrationErrorTimer,
      setPendingRegistrationError: (value) => _pendingRegistrationError = value,
      clearErrorSafe: _clearErrorSafe,
      handleRegistrationFailure: _handleRegistrationFailure,
      scheduleReconnect: _scheduleReconnect,
      maybeStartHealthWatchdog: _maybeStartHealthWatchdog,
      getState: () => state,
      commitState: (next) => _commit(next),
    );
    final initialStatus =
        ref.read(authNotifierProvider).value?.status ?? AuthStatus.unknown;
    _lastAuthStatus ??= initialStatus;
    if (!_authListenerActive) {
      _authListenerActive = true;
      _authListener.start(ref, (previous, next) {
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
    _connectivityListener = CallConnectivityListener(
      connectivityService: _connectivityService,
      isDisposed: () => _disposed,
      onOnlineChanged: _handleConnectivityChanged,
      onInitialOnlineResolved: (online) {
        _lastKnownOnline = online;
        if (online) {
          debugPrint(
            '[CALLS_CONN] net online (init) -> ensureBootstrapped reason=net-online-init',
          );
          ensureBootstrapped('net-online-init');
          _maybeStartHealthWatchdog();
        }
      },
      logSnapshot: (tag) {
        logConnectivitySnapshot(tag);
        debugDumpConnectivityAndSipHealth(tag);
      },
    );
    unawaited(_connectivityListener.start());
    Future.microtask(
      () => _maybeBootstrapFromCurrentSnapshot('build-snapshot'),
    );
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
        if (_disposed) return;
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
      _connectivityListener.dispose();
      _reconnectScheduler.cancel();
      _healthWatchdog.stop();
      _authListener.dispose();
      _cancelDialTimeout();
      _cancelRegistrationErrorTimer();
      _cancelFailureTimer();
      _cancelRetrySuppressionTimer();
      _disposeWatchdog();
      unawaited(_releaseAudioFocus());
      for (final timer in _endedCleanupTimers.values) {
        timer.cancel();
      }
      _endedCleanupTimers.clear();
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
    _bootstrapService.bootstrapIfNeeded(
      isDisposed: () => _disposed,
      debugMode: kDebugMode,
      bootstrapDone: _bootstrapDone,
      bootstrapInFlight: _bootstrapInFlight,
      bootstrapScheduled: _bootstrapScheduled,
      snapshot: snapshot,
      debugPrint: debugPrint,
      prerequisitesSkipReason: () => _bootstrapPrerequisitesSkipReason(),
      setBootstrapInFlight: (value) => _bootstrapInFlight = value,
      markBootstrapDone: () => _bootstrapDone = true,
      setBootstrapCompletedAt: (date) => _bootstrapCompletedAt = date,
      syncForegroundServiceState: _syncForegroundServiceState,
      handleIncomingCallHint: handleIncomingCallHintIfAny,
      maybeStartHealthWatchdog: _maybeStartHealthWatchdog,
    );
  }

  void ensureBootstrapped(String reason) {
    if (_disposed) return;
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
    if (_disposed) return;
    final now = DateTime.now();
    if (!online) {
      debugPrint('[CALLS_CONN] net offline');
      _lastKnownOnline = false;
      _lastOnlineHandledAt = null;
      _reconnectScheduler.cancel();
      _reconnectInFlight = false;
      _reconnectScheduler.resetBackoff();
      _lastNetworkActivityAt = null;
      _lastSipRegisteredAt = null;
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
    final activeStatus = state.activeCall?.status;
    _debugDumper.dumpShort(
      disposed: _disposed,
      kDebugModeEnabled: kDebugMode,
      tag: tag,
      authStatusName: authStatus.name,
      online: _lastKnownOnline,
      bootstrapScheduled: _bootstrapScheduled,
      bootstrapDone: _bootstrapDone,
      bootstrapInFlight: _bootstrapInFlight,
      lastNetworkActivityAt: _lastNetworkActivityAt,
      backoffIndex: _reconnectScheduler.backoffIndex,
      activeCallId: state.activeCallId,
      activeCallStatus: activeStatus,
      lastSipRegisteredAt: _lastSipRegisteredAt,
      log: debugPrint,
    );
  }

  bool _isSipHealthyNow() {
    if (!_isRegistered || _lastNetworkActivityAt == null) return false;
    return DateTime.now().difference(_lastNetworkActivityAt!) <=
        _sipHealthTimeout;
  }

  void _maybeBootstrapFromCurrentSnapshot(String reason) {
    if (_disposed) return;
    if (_bootstrapDone || _bootstrapInFlight) return;
    final skip = _bootstrapPrerequisitesSkipReason();
    if (skip != null) return;
    debugPrint('[CALLS_CONN] snapshot -> ensureBootstrapped reason=$reason');
    ensureBootstrapped(reason);
    _maybeStartHealthWatchdog();
    debugDumpConnectivityAndSipHealth(reason);
  }

  void debugDumpConnectivityAndSipHealth(String tag) {
    final AuthStatus authStatus =
        ref.read(authNotifierProvider).value?.status ?? AuthStatus.unknown;
    _debugDumper.dump(
      disposed: _disposed,
      kDebugModeEnabled: kDebugMode,
      tag: tag,
      authStatusName: authStatus.name,
      online: _lastKnownOnline,
      bootstrapScheduled: _bootstrapScheduled,
      bootstrapDone: _bootstrapDone,
      bootstrapInFlight: _bootstrapInFlight,
      engineRegistered: _isRegistered,
      stateRegistered: state.isRegistered,
      lastRegistrationStateName: _lastRegistrationState.name,
      lastNetworkActivityAt: _lastNetworkActivityAt,
      healthTimerActive: _healthWatchdog.isRunning,
      reconnectTimerActive: _reconnectScheduler.hasScheduledTimer,
      reconnectInFlight: _reconnectInFlight,
      backoffIndex: _reconnectScheduler.backoffIndex,
      activeCallId: state.activeCallId ?? '<none>',
      activeCallStatus: state.activeCall?.status,
      log: debugPrint,
    );
  }

  void _maybeStartHealthWatchdog() {
    if (_disposed) return;
    final AuthStatus authStatus =
        ref.read(authNotifierProvider).value?.status ?? AuthStatus.unknown;
    if (_shouldStopHealthWatchdogNow(authStatus)) {
      _stopHealthWatchdog();
      return;
    }
    if (!_shouldStartHealthWatchdogNow(authStatus)) {
      return;
    }
    _healthStartedAt = DateTime.now();
    _healthWatchdog.start();
  }

  void _stopHealthWatchdog() {
    _healthWatchdog.stop();
    _healthStartedAt = null;
  }

  void _checkSipHealthTick() {
    if (_disposed) return;
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

  bool _shouldStartHealthWatchdogNow(AuthStatus authStatus) {
    final authenticated = authStatus == AuthStatus.authenticated;
    return CallSipHealthPolicy.shouldStartWatchdog(
      online: _lastKnownOnline,
      authenticated: authenticated,
      watchdogRunning: _healthWatchdog.isRunning,
      sipHealthyNow: _isSipHealthyNow(),
    );
  }

  bool _shouldStopHealthWatchdogNow(AuthStatus authStatus) {
    final authenticated = authStatus == AuthStatus.authenticated;
    return CallSipHealthPolicy.shouldStopWatchdog(
      online: _lastKnownOnline,
      authenticated: authenticated,
      sipHealthyNow: _isSipHealthyNow(),
    );
  }

  void _scheduleReconnect(String reason) {
    if (_disposed) return;
    final authStatus = currentAuthStatus(ref);
    final callIdForLogs = activeCallIdForLogs(state.activeCallId);
    _reconnectService.scheduleReconnect(
      reason: reason,
      disposed: _disposed,
      authStatus: authStatus,
      activeCallIdForLogs: callIdForLogs,
      lastKnownOnline: _lastKnownOnline,
      hasActiveCall: _hasActiveCall,
      reconnectInFlight: _reconnectInFlight,
      isRegistered: _isRegistered,
      lastNetworkActivityAt: _lastNetworkActivityAt,
      reconnectScheduler: _reconnectScheduler,
      log: debugPrint,
      debugDumpConnectivityAndSipHealth: debugDumpConnectivityAndSipHealth,
      onFire: () => _performReconnect(reason),
      now: DateTime.now(),
    );
  }

  Future<void> _performReconnect(String reason) async {
    if (_disposed) return;
    final authStatus = currentAuthStatus(ref);
    final callIdForLogs = activeCallIdForLogs(state.activeCallId);
    await _reconnectService.performReconnect(
      reason: reason,
      disposed: _disposed,
      authStatus: authStatus,
      activeCallIdForLogs: callIdForLogs,
      lastKnownOnline: _lastKnownOnline,
      hasActiveCall: _hasActiveCall,
      reconnectInFlight: _reconnectInFlight,
      log: debugPrint,
      executeReconnect: (executeReason) async {
        final reconnectUser = _lastKnownUser ?? _incomingUser;
        _reconnectInFlight = true;
        try {
          return await _reconnectExecutor.reconnect(
            reason: executeReason,
            reconnectUser: reconnectUser,
            ensureRegistered: ensureRegistered,
          );
        } finally {
          _reconnectInFlight = false;
        }
      },
    );
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

  void _commitSafe(CallState next, {bool syncFgs = true}) {
    if (!_alive) return;
    final sanitized = _sanitizeActiveCallId(next, 'commitSafe');
    _commit(sanitized, syncFgs: syncFgs);
  }

  Future<void> _onEvent(SipEvent event) async {
    if (_disposed) return;
    final now = DateTime.now();
    if (_registrationHandler.handle(event, now)) return;

    final sipCallId = event.callId;
    if (sipCallId == null) return;

    final effectiveId = _sipToLocalCallId[sipCallId] ?? sipCallId;
    var callId = effectiveId;
    final localId = _sipToLocalCallId.containsKey(callId)
        ? _sipToLocalCallId[callId]!
        : callId;

    final status = _mapStatus(event.type);
    if (_handleRecentlyEndedOrDeadCall(
      event: event,
      callId: callId,
      sipCallId: sipCallId,
      status: status,
      now: now,
      localId: localId,
    )) {
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
    if (_applyPendingCallMapping(
      event: event,
      callId: callId,
      callIdUnknown: callIdUnknown,
      pendingId: pendingId,
      sipCallId: sipCallId,
    )) {
      callId = _pendingCallId!;
      pendingId = callId;
      callIdUnknown = false;
    }

    final didAdoptIncoming = _handleIncomingAdoption(
      event: event,
      callId: callId,
      sipCallId: sipCallId,
      now: now,
      hasActive: hasActive,
      isBusy: isBusy,
      callIdUnknown: callIdUnknown,
    );
    if (didAdoptIncoming) {
      activeId = state.activeCallId;
      activeCall = state.activeCall;
      hasActive = activeCall != null && activeCall.status != CallStatus.ended;
      callIdUnknown = false;
      pendingId = _pendingCallId;
    }

    if (_handleNonRelevantCall(callId, activeId, pendingId)) {
      return;
    }

    if (_handleStitchingAndBusy(
      event: event,
      callId: callId,
      pendingId: pendingId,
      activeId: activeId,
      hasActive: hasActive,
      now: now,
      isBusy: isBusy,
      callIdUnknown: callIdUnknown,
    )) {
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
    if (_handleLateNonDialingEvent(
      event: event,
      status: status,
      callId: callId,
      sipCallId: sipCallId,
      previous: previous,
      localId: localId,
    )) {
      return;
    }

    if (status == CallStatus.ended) {
      await _handleCallEnded(event, callId, previousState);
      return;
    }

    await _handleCallStateChange(
      event: event,
      status: status,
      callId: callId,
      previousState: previousState,
      previous: previous,
      pendingCallId: pendingCallId,
    );
  }

  bool _handleRecentlyEndedOrDeadCall({
    required SipEvent event,
    required String callId,
    required String sipCallId,
    required CallStatus status,
    required DateTime now,
    required String localId,
  }) {
    _recentlyEnded.removeWhere(
      (_, ts) => now.difference(ts) > _recentlyEndedTtl,
    );
    if (_recentlyEnded.containsKey(callId) ||
        _recentlyEnded.containsKey(sipCallId)) {
      debugPrint(
        '[CALLS] ignoring late sip event event=${event.type.name} sipId=$sipCallId effectiveId=$callId (recently ended)',
      );
      return true;
    }
    final allowAlive =
        status == CallStatus.dialing || status == CallStatus.ringing;
    if (!allowAlive && !_isCallAlive(callId) && !_isCallAlive(sipCallId)) {
      debugPrint(
        '[CALLS] ignoring event for dead call event=${event.type.name} sipId=$sipCallId effectiveId=$callId localId=$localId dead=true',
      );
      return true;
    }
    return false;
  }

  bool _applyPendingCallMapping({
    required SipEvent event,
    required String callId,
    required bool callIdUnknown,
    required String? pendingId,
    required String sipCallId,
  }) {
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
      _pendingCallId = localPendingId;
      _pendingLocalCallId = null;
      return true;
    }
    return false;
  }

  bool _handleIncomingAdoption({
    required SipEvent event,
    required String callId,
    required String sipCallId,
    required DateTime now,
    required bool hasActive,
    required bool isBusy,
    required bool callIdUnknown,
  }) {
    final shouldAdoptIncoming =
        event.type == SipEventType.ringing &&
        callIdUnknown &&
        !hasActive &&
        !isBusy;
    if (!shouldAdoptIncoming) return false;
    final alreadyCancelled =
        _recentlyEnded.containsKey(callId) ||
        _recentlyEnded.containsKey(sipCallId);
    if (alreadyCancelled) {
      debugPrint(
        '[INCOMING] suppress adopt for cancelled call sipId=$sipCallId effectiveId=$callId',
      );
      return false;
    }
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
    _phase = _CallPhase.ringing;
    debugPrint(
      '[INCOMING] adopted -> active ringing callId=$callId sipId=$sipCallId',
    );
    return true;
  }

  bool _handleNonRelevantCall(
    String callId,
    String? activeId,
    String? pendingId,
  ) {
    if (!_isRelevantCall(callId, activeId)) {
      debugPrint(
        '[SIP] ignoring event for non-active callId=$callId active=$activeId pending=$pendingId reason=non-relevant',
      );
      return true;
    }
    return false;
  }

  bool _handleStitchingAndBusy({
    required SipEvent event,
    required String callId,
    required String? pendingId,
    required String? activeId,
    required bool hasActive,
    required DateTime now,
    required bool isBusy,
    required bool callIdUnknown,
  }) {
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
        return true;
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
        return true;
      }
      debugPrint(
        '[INCOMING] ignoring stray ${event.type.name} callId=$callId active=$activeId pending=$pendingId reason=not-allowed',
      );
      return true;
    }
    return false;
  }

  bool _handleLateNonDialingEvent({
    required SipEvent event,
    required CallStatus status,
    required String callId,
    required String sipCallId,
    CallInfo? previous,
    required String localId,
  }) {
    if (previous == null &&
        status != CallStatus.dialing &&
        status != CallStatus.ringing) {
      debugPrint(
        '[CALLS] ignoring late non-dialing/ringing event=${event.type.name} sipId=$sipCallId effectiveId=$callId localId=$localId',
      );
      return true;
    }
    return false;
  }

  Future<void> _handleCallEnded(
    SipEvent event,
    String callId,
    CallState previousState,
  ) async {
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
  }

  Future<void> _handleCallStateChange({
    required SipEvent event,
    required CallStatus status,
    required String callId,
    required CallState previousState,
    CallInfo? previous,
    String? pendingCallId,
  }) async {
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

  Future<void> _drainPendingCallActions() {
    return _bootstrapService.drainPendingCallActions(
      isDisposed: () => _disposed,
      debugMode: kDebugMode,
      handleIncomingCallHint: handleIncomingCallHintIfAny,
      incomingRegistrationReady: () => _incomingRegistrationReady,
      fetchPendingCallActions: () =>
          IncomingNotificationService.drainPendingCallActions(),
      log: debugPrint,
      processedPendingCallActions: _processedPendingCallActions,
      pendingCallActionDedupTtl: _pendingCallActionDedupTtl,
      isCallAlive: _isCallAlive,
      notifCleanup: _notifCleanup,
      answerFromNotification: answerFromNotification,
      declineFromNotification: declineFromNotification,
    );
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

  void _setErrorSafe(String message) {
    if (!_alive) return;
    _setError(message);
  }

  void _clearErrorSafe() {
    if (!_alive) return;
    _clearError();
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
      if (_disposed) return;
      if (_isRegistered) {
        _pendingRegistrationError = null;
        return;
      }
      _setErrorSafe(_pendingRegistrationError ?? 'SIP registration failed');
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
      if (_disposed) return;
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

  CallState _sanitizeActiveCallId(CallState snapshot, String reason) {
    final activeId = snapshot.activeCallId;
    if (activeId == null) return snapshot;
    final call = snapshot.calls[activeId];
    if (call == null) {
      debugPrint(
        '[CALLS] sanitize activeCallId: missing in calls -> clearing activeCallId '
        'id=$activeId reason=$reason calls=${snapshot.calls.length}',
      );
      return snapshot.copyWith(activeCallId: null);
    }
    if (call.status == CallStatus.ended) {
      debugPrint(
        '[CALLS] sanitize activeCallId: ended -> clearing activeCallId '
        'id=$activeId reason=$reason status=${call.status}',
      );
      return snapshot.copyWith(activeCallId: null);
    }
    return snapshot;
  }

  bool _isBusyForDial(CallState s) {
    final hasActiveId = s.activeCallId != null;
    final hasOngoingCalls = s.calls.values.any(
      (call) => call.status != CallStatus.ended,
    );
    return hasActiveId ||
        hasOngoingCalls ||
        _pendingCallId != null ||
        _pendingLocalCallId != null;
  }

  bool _isDialPhaseAllowed() {
    return _phase == _CallPhase.idle || _phase == _CallPhase.ending;
  }

  static const Set<String> _graceDelayReasons = {
    'sip-error',
    'dial-timeout',
    'startCall-failed',
  };

  bool _shouldGraceDelayForReason(String reason) {
    return _graceDelayReasons.contains(reason);
  }

  bool _wasEarlyPhase(CallStatus? status) {
    return status != null &&
        status != CallStatus.connected &&
        status != CallStatus.ended;
  }

  bool _hasLiveCalls(Iterable<CallInfo> calls) {
    return calls.any((call) => call.status != CallStatus.ended);
  }

  bool canStartOutgoingCallUi(CallState s, String rawNumber) {
    final trimmed = rawNumber.trim();
    if (trimmed.isEmpty || !s.isRegistered) return false;
    final sanitized = _sanitizeActiveCallId(s, 'canStartOutgoingCallUi');
    final hasOngoing = sanitized.calls.values.any(
      (call) => call.status != CallStatus.ended,
    );
    return sanitized.activeCallId == null && !hasOngoing;
  }

  void _resetDialLocksIfIdle(CallState snapshot, String reason) {
    final hasActiveCall = snapshot.activeCallId != null;
    final hasOngoingCalls = snapshot.calls.values.any(
      (call) => call.status != CallStatus.ended,
    );
    if (hasActiveCall ||
        hasOngoingCalls ||
        _pendingCallId != null ||
        _pendingLocalCallId != null) {
      return;
    }
    var didReset = false;
    if (_phase != _CallPhase.idle) {
      _phase = _CallPhase.idle;
      didReset = true;
    }
    if (_dialTimeoutTimer != null || _dialTimeoutCallId != null) {
      _cancelDialTimeout();
      didReset = true;
    }
    if (didReset) {
      debugPrint('[CALLS] idle cleanup: reset dial locks reason=$reason');
    }
  }

  void _scheduleEndedCleanup({
    required String primaryId,
    String? secondaryId,
    required DateTime endedAt,
    required String reason,
  }) {
    _endedCleanupTimers.remove(primaryId)?.cancel();
    if (!_alive) return;

    final timer = Timer(_endedCleanupDelay, () {
      _endedCleanupTimers.remove(primaryId);
      if (!_alive) return;
      final updatedCalls = Map<String, CallInfo>.from(state.calls);
      var removed = false;

      bool removeIfMatched(String id) {
        final call = updatedCalls[id];
        if (call != null &&
            call.status == CallStatus.ended &&
            call.endedAt == endedAt) {
          updatedCalls.remove(id);
          return true;
        }
        return false;
      }

      if (removeIfMatched(primaryId)) {
        removed = true;
      }
      if (secondaryId != null && secondaryId != primaryId) {
        if (removeIfMatched(secondaryId)) {
          removed = true;
        }
      }
      if (!removed) return;
      final nextState = state.copyWith(calls: updatedCalls);
      final sanitized = _sanitizeActiveCallId(nextState, 'ended-cleanup');
      _commitSafe(sanitized);
      _resetDialLocksIfIdle(sanitized, 'ended-cleanup');
      debugPrint(
        '[CALLS] ended cleanup fired primary=$primaryId secondary=${secondaryId ?? "<none>"} '
        'reason=$reason calls=${sanitized.calls.length}',
      );
    });
    _endedCleanupTimers[primaryId] = timer;
    debugPrint(
      '[CALLS] scheduled ended cleanup primary=$primaryId secondary=${secondaryId ?? "<none>"} '
      'delay=${_endedCleanupDelay.inMilliseconds}ms reason=$reason',
    );
  }

  Future<void> _refreshAudioRoute() async {
    if (_disposed) return;
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
      if (_disposed) return;
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
    if (_disposed) return;
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
    if (_disposed) return;
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
      if (_disposed) return;
      if (_failureTimerCallId != callId) return;
      if (state.activeCall?.id != callId) return;
      if (state.watchdogState.status != CallWatchdogStatus.failed) return;
      if (_userInitiatedRetry) {
        debugPrint('Watchdog hangup suppressed for $callId (user retry)');
        return;
      }
      debugPrint('Watchdog hangup timer expired for $callId');
      _watchdogErrorActive = true;
      _setErrorSafe('Network is unstable, ending call');
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
      if (_disposed) return;
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
    if (!_disposed &&
        _watchdogErrorActive &&
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
    if (!_disposed && state.watchdogState.status != CallWatchdogStatus.ok) {
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
