import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:app/config/app_theme.dart';
import 'package:app/core/storage/battery_optimization_prompt_storage.dart';
import 'package:app/features/auth/state/auth_notifier.dart';
import 'package:app/features/auth/state/auth_state.dart';
import 'package:app/features/calls/incoming/incoming_wake_coordinator.dart';
import 'package:app/features/calls/state/call_notifier.dart';
import 'package:app/platform/system_settings.dart';
import 'package:app/services/app_lifecycle_tracker.dart';
import 'package:app/services/firebase_messaging_service.dart';
import 'package:app/services/incoming_notification_service.dart';
import 'package:app/ui/pages/call_screen.dart';
import 'package:app/ui/pages/login_page.dart';
import 'package:app/ui/pages/home_page.dart';

class App extends ConsumerWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: const _AuthGate(),
    );
  }
}

class _AuthGate extends ConsumerStatefulWidget {
  const _AuthGate();

  @override
  ConsumerState<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends ConsumerState<_AuthGate>
    with WidgetsBindingObserver {
  ProviderSubscription<AsyncValue<AuthState>>? _authSubscription;
  ProviderSubscription<CallState>? _callStateSubscription;
  String? _incomingScreenCallId;
  String? _scheduledCallId;
  String? _deferredCallId;
  late bool _isResumed;
  bool _batteryPromptInFlight = false;
  bool _batteryPromptScheduled = false;
  DateTime? _lastIncomingActivityAt;

  @override
  void initState() {
    super.initState();
    final lifecycleState = WidgetsBinding.instance.lifecycleState;
    _isResumed =
        lifecycleState == AppLifecycleState.resumed || lifecycleState == null;
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _lastIncomingActivityAt = DateTime.now();
      ref
          .read(incomingWakeCoordinatorProvider)
          .checkPendingHint()
          .whenComplete(() {
        _lastIncomingActivityAt = DateTime.now();
        _handlePendingCallAction();
      });
    });
    _authSubscription = ref.listenManual<AsyncValue<AuthState>>(
      authNotifierProvider,
      (previous, next) => _handleAuthState(next),
    );
    _handleAuthState(ref.read(authNotifierProvider));
    _callStateSubscription = ref.listenManual<CallState>(
      callControllerProvider,
      (previous, next) => _handleCallStateChange(previous, next),
    );
  }

  bool _requestedFcmPermission = false;

  void _handleAuthState(AsyncValue<AuthState> authState) {
    final status = authState.value?.status ?? AuthStatus.unknown;
    final authenticated = status == AuthStatus.authenticated;
    if (authenticated && !_requestedFcmPermission) {
      _requestedFcmPermission = true;
      FirebaseMessagingService.requestPermission();
    } else if (!authenticated) {
      _requestedFcmPermission = false;
    }
    if (authenticated) {
      unawaited(_maybeAskBatteryOptimizations());
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authNotifierProvider);

    return auth.when(
      loading: () => const _Splash(),
      error: (e, _) => LoginPage(error: e.toString()),
      data: (s) {
        return switch (s.status) {
          AuthStatus.authenticated => const HomePage(),
          AuthStatus.unauthenticated => LoginPage(error: s.error),
          AuthStatus.unknown => const _Splash(),
        };
      },
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authSubscription?.close();
    _callStateSubscription?.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    AppLifecycleTracker.update(state);
    _isResumed = state == AppLifecycleState.resumed;
    if (state == AppLifecycleState.resumed) {
      if (_deferredCallId != null) {
        if (_deferredCallId == _incomingScreenCallId) {
          _deferredCallId = null;
        } else {
          _schedulePush(_deferredCallId!);
          _deferredCallId = null;
        }
      }
      _batteryPromptScheduled = false;
      _batteryPromptInFlight = false;
      _lastIncomingActivityAt = DateTime.now();
      ref
          .read(incomingWakeCoordinatorProvider)
          .checkPendingHint()
          .whenComplete(() {
            _lastIncomingActivityAt = DateTime.now();
            _handlePendingCallAction();
          });
      unawaited(_maybeAskBatteryOptimizations());
    } else {
      _batteryPromptScheduled = false;
      _lastIncomingActivityAt = null;
    }
  }

  Future<void> _maybeAskBatteryOptimizations() async {
    if (!Platform.isAndroid) return;
    final status =
        ref.read(authNotifierProvider).value?.status ?? AuthStatus.unknown;
    if (status != AuthStatus.authenticated) return;
    if (_batteryPromptInFlight || _batteryPromptScheduled) return;
    final promptShown =
        await BatteryOptimizationPromptStorage.readPromptShown();
    if (promptShown) {
      debugPrint('[CALLS] battery optimization prompt already shown, skipping');
      return;
    }
    final now = DateTime.now();
    if (_lastIncomingActivityAt != null &&
        now.difference(_lastIncomingActivityAt!) < const Duration(seconds: 10)) {
      debugPrint(
        '[CALLS] battery prompt suppressed: recent incoming activity',
      );
      return;
    }
    final callState = ref.read(callControllerProvider);
    final activeId = callState.activeCallId;
    final activeCall = activeId != null ? callState.calls[activeId] : null;
    if (activeId != null &&
        activeCall != null &&
        activeCall.status != CallStatus.ended) {
      debugPrint(
        '[CALLS] battery prompt suppressed: call in progress activeId=$activeId status=${activeCall.status.name}',
      );
      return;
    }
    if (!mounted || !_isResumed) return;
    _batteryPromptScheduled = true;
    _batteryPromptInFlight = true;
    try {
      final batteryDisabled = await ref
          .read(callControllerProvider.notifier)
          .isBatteryOptimizationDisabled();
      if (batteryDisabled) {
        await BatteryOptimizationPromptStorage.markPromptShown();
        return;
      }
      if (!mounted || !_isResumed) return;
      debugPrint('[CALLS] showing battery optimization prompt');
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Allow background calling'),
          content: const Text(
            'Disable battery optimizations so incoming calls stay reliable even when the screen is off.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                SystemSettings.openIgnoreBatteryOptimizations();
                Navigator.of(ctx).pop();
              },
              child: const Text('Open settings'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Not now'),
            ),
          ],
        ),
      );
      await BatteryOptimizationPromptStorage.markPromptShown();
    } finally {
      _batteryPromptInFlight = false;
    }
  }

  Future<void> _handlePendingCallAction() async {
    _lastIncomingActivityAt = DateTime.now();
    final rawAction = await IncomingNotificationService.readCallAction();
    if (rawAction == null) return;
    final callId =
        rawAction['call_id']?.toString() ?? rawAction['callId']?.toString();
    final action = (rawAction['action'] ?? rawAction['type'])?.toString();
    final timestampMillis = _timestampToMillis(
      rawAction['timestamp'] ?? rawAction['ts'],
    );
    if (callId == null || action == null || timestampMillis == null) {
      await IncomingNotificationService.clearCallAction();
      return;
    }
    final actionAge = DateTime.now().difference(
      DateTime.fromMillisecondsSinceEpoch(timestampMillis),
    );
    if (actionAge > const Duration(seconds: 30)) {
      await IncomingNotificationService.clearCallAction();
      return;
    }

    final callState = ref.read(callControllerProvider);
    final callInfo = callState.calls[callId];
    if (callInfo?.status == CallStatus.ended) {
      await IncomingNotificationService.clearCallAction();
      return;
    }

    final notifier = ref.read(callControllerProvider.notifier);
    var executed = false;
    if (action == 'answer') {
      await notifier.answerFromNotification(callId);
      executed = true;
    } else if (action == 'decline') {
      await notifier.declineFromNotification(callId);
      executed = true;
    } else {
      await IncomingNotificationService.clearCallAction();
      return;
    }

    if (executed) {
      await IncomingNotificationService.clearCallAction();
    }
  }

  void _handleCallStateChange(CallState? previous, CallState next) {
    final authStatus =
        ref.read(authNotifierProvider).value?.status ?? AuthStatus.unknown;
    if (authStatus != AuthStatus.authenticated) {
      return;
    }
    final newCallId = next.activeCallId;
    final previousCallId = previous?.activeCallId;
    if (newCallId != null && newCallId != previousCallId) {
      _schedulePush(newCallId);
    }
    final activeCall = next.activeCall;
    if (activeCall == null || activeCall.status == CallStatus.ended) {
      _deferredCallId = null;
    }
  }

  void _pushCallScreen(String callId) {
    if (!mounted) return;
    if (_incomingScreenCallId == callId) return;
    final navigator = Navigator.of(context, rootNavigator: true);
    final previousCallId = _incomingScreenCallId;
    _incomingScreenCallId = callId;
    final route = MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => CallScreen(callId: callId),
    );
    if (previousCallId != null) {
      navigator.pushReplacement(route).then((_) {
        if (_incomingScreenCallId == callId) {
          _incomingScreenCallId = null;
        }
      });
      return;
    }
    navigator.push(route).then((_) {
      if (_incomingScreenCallId == callId) {
        _incomingScreenCallId = null;
      }
    });
  }

  void _schedulePush(String callId) {
    if (!_isResumed) {
      _deferredCallId = callId;
      return;
    }
    if (_incomingScreenCallId == callId) return;
    if (_scheduledCallId == callId) return;
    _scheduledCallId = callId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_scheduledCallId != callId) return;
      _scheduledCallId = null;
      _pushCallScreen(callId);
    });
  }

  int? _timestampToMillis(Object? value) {
    if (value is int) return value;
    if (value is double) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
