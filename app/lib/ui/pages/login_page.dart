import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

import 'package:app/core/providers.dart';
import 'package:app/features/auth/state/auth_notifier.dart';
import 'package:app/features/auth/state/auth_state.dart';
import 'package:app/ui/widgets/labeled_input.dart';
import 'package:app/ui/widgets/loading_button.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key, this.error});

  final String? error;

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();

  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();
  final _localAuth = LocalAuthentication();

  bool _biometricAvailable = false;
  bool _isAuthenticatingBiometric = false;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _emailFocus.requestFocus();
      _checkBiometricSupport();
    });
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  bool _validEmail(String v) => v.contains('@') && v.contains('.');

  Future<T> _withSubmission<T>(Future<T> Function() action) async {
    setState(() => _isSubmitting = true);
    try {
      return await action();
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Future<void> _login() async {
    final email = _email.text.trim();
    final password = _password.text;

    if (!_validEmail(email)) {
      _emailFocus.requestFocus();
      _toast('Please enter a valid email');
      return;
    }

    if (password.isEmpty) {
      _passwordFocus.requestFocus();
      _toast('Please enter password');
      return;
    }

    await _withSubmission(
      () => ref.read(authNotifierProvider.notifier).login(email, password),
    );
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _checkBiometricSupport() async {
    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      final isSupported = await _localAuth.isDeviceSupported();
      final tokens = await ref
          .read(biometricTokensStorageProvider)
          .readTokens();
      final available = (canCheck || isSupported) && tokens != null;
      if (!mounted) return;
      setState(() => _biometricAvailable = available);
    } catch (_) {
      // ignore
    }
  }

  Future<void> _authenticateWithBiometrics() async {
    if (_isAuthenticatingBiometric) return;

    await _withSubmission(() async {
      setState(() => _isAuthenticatingBiometric = true);
      try {
        final didAuthenticate = await _localAuth.authenticate(
          localizedReason: 'Please authenticate with Face ID or fingerprint',
          biometricOnly: true,
          persistAcrossBackgrounding: true,
        );

        if (!didAuthenticate) {
          _toast('Biometric check was not confirmed');
          return;
        }

        await ref.read(authNotifierProvider.notifier).loginWithBiometrics();
      } catch (error) {
        debugPrint('Biometric auth failed: $error');
        _toast('Failed to perform biometric authentication');
      } finally {
        setState(() => _isAuthenticatingBiometric = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final authAsync = ref.watch(authNotifierProvider);
    final isBusy = _isSubmitting || authAsync.isLoading;

    // 1) error from AsyncValue.error
    // 2) error from AuthState.unauthenticated(error)
    // 3) error passed from the parent
    String? error = widget.error;

    authAsync.when(
      loading: () {},
      error: (e, _) => error = e.toString(),
      data: (s) {
        if (s.status == AuthStatus.unauthenticated) {
          error = s.error ?? error;
        }
      },
    );

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: AutofillGroup(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Log in',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 18),

                    LabeledInput(
                      label: 'Your Email*',
                      hint: 'Enter email',
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      focusNode: _emailFocus,
                      textInputAction: TextInputAction.next,
                      onSubmitted: (_) => _passwordFocus.requestFocus(),
                      enabled: !isBusy,
                      autofillHints: const [
                        AutofillHints.username,
                        AutofillHints.email,
                      ],
                    ),
                    const SizedBox(height: 14),

                    LabeledInput(
                      label: 'Password*',
                      hint: 'Enter password',
                      controller: _password,
                      obscure: true,
                      focusNode: _passwordFocus,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => isBusy ? null : _login(),
                      enabled: !isBusy,
                      autofillHints: const [AutofillHints.password],
                    ),

                    if (error != null && error!.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        error!,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.error,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],

                    const SizedBox(height: 14),
                    LoadingButton(
                      onPressed: isBusy ? null : _login,
                      isLoading: _isSubmitting,
                      child: const Text('Log in'),
                    ),
                    if (_biometricAvailable) ...[
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: isBusy || _isAuthenticatingBiometric
                            ? null
                            : _authenticateWithBiometrics,
                        icon: const Icon(Icons.fingerprint),
                        label: Text(
                          _isAuthenticatingBiometric
                              ? 'Waiting for biometrics…'
                              : 'Log in with Face ID/fingerprint',
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
