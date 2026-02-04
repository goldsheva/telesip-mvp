import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:app/features/auth/state/auth_notifier.dart';
import 'package:app/features/auth/state/auth_state.dart';
import 'package:app/ui/widgets/labeled_input.dart';

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _emailFocus.requestFocus());
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

    await ref.read(authNotifierProvider.notifier).login(email, password);
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final authAsync = ref.watch(authNotifierProvider);
    final isLoading = authAsync.isLoading;

    // 1) ошибка из AsyncValue.error
    // 2) ошибка из AuthState.unauthenticated(error)
    // 3) ошибка, проброшенная сверху
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
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
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
                      enabled: !isLoading,
                      autofillHints: const [AutofillHints.username, AutofillHints.email],
                    ),
                    const SizedBox(height: 14),

                    LabeledInput(
                      label: 'Password*',
                      hint: 'Enter password',
                      controller: _password,
                      obscure: true,
                      focusNode: _passwordFocus,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => isLoading ? null : _login(),
                      enabled: !isLoading,
                      autofillHints: const [AutofillHints.password],
                    ),

                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: isLoading ? null : () {},
                        child: const Text('Forgot password?'),
                      ),
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
                    ElevatedButton(
                      onPressed: isLoading ? null : _login,
                      child: isLoading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Log in'),
                    ),
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
