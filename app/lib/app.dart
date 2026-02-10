import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:app/config/app_theme.dart';
import 'package:app/features/auth/state/auth_notifier.dart';
import 'package:app/features/auth/state/auth_state.dart';
import 'package:app/features/calls/incoming/incoming_wake_coordinator.dart';
import 'package:app/features/calls/state/call_notifier.dart';
import 'package:app/services/app_lifecycle_tracker.dart';
import 'package:app/services/firebase_messaging_service.dart';
import 'package:app/services/incoming_notification_service.dart';
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
  String? _incomingDialogCallId;
  BuildContext? _incomingDialogContext;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(incomingWakeCoordinatorProvider)
          .checkPendingHint()
          .whenComplete(() => _handlePendingCallAction());
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
    if (state == AppLifecycleState.resumed) {
      ref
          .read(incomingWakeCoordinatorProvider)
          .checkPendingHint()
          .whenComplete(() => _handlePendingCallAction());
    }
  }

  Future<void> _handlePendingCallAction() async {
    final rawAction = await IncomingNotificationService.readCallAction();
    if (rawAction == null) return;
    final callId = rawAction['call_id']?.toString();
    final action = rawAction['action']?.toString();
    final timestampMillis = _timestampToMillis(rawAction['timestamp']);
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
    final hasCall = callInfo != null || callState.activeCallId == callId;
    if (!hasCall) return;
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
    final currentCall = next.activeCall;
    final wasRinging = previous?.activeCall?.status == CallStatus.ringing;
    final isRinging = currentCall?.status == CallStatus.ringing;
    if (isRinging && !wasRinging && currentCall != null) {
      _showIncomingDialog(currentCall.id);
      return;
    }
    if (_incomingDialogCallId != null &&
        (currentCall == null || currentCall.status != CallStatus.ringing)) {
      _closeIncomingDialog();
    }
  }

  void _showIncomingDialog(String callId) {
    if (!mounted) return;
    if (_incomingDialogCallId == callId) return;
    _closeIncomingDialog();
    _incomingDialogCallId = callId;
    final notifier = ref.read(callControllerProvider.notifier);
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          _incomingDialogContext = dialogContext;
          return AlertDialog(
            title: const Text('Incoming call'),
            actions: [
              TextButton(
                onPressed: () async {
                  await notifier.decline(callId);
                  _closeIncomingDialog();
                },
                child: const Text('Decline'),
              ),
              ElevatedButton(
                onPressed: () async {
                  await notifier.answer(callId);
                  _closeIncomingDialog();
                },
                child: const Text('Answer'),
              ),
            ],
          );
        },
      ).then((_) {
        if (_incomingDialogCallId == callId) {
          _incomingDialogCallId = null;
        }
        _incomingDialogContext = null;
      }),
    );
  }

  void _closeIncomingDialog() {
    final dialogContext = _incomingDialogContext;
    _incomingDialogCallId = null;
    _incomingDialogContext = null;
    if (dialogContext != null) {
      Navigator.of(dialogContext).pop();
    }
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
