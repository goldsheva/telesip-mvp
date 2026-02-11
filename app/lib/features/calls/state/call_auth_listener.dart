import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:app/features/auth/state/auth_state.dart';
import 'package:app/features/auth/state/auth_notifier.dart';

class CallAuthListener {
  CallAuthListener({required this.isDisposed});

  final bool Function() isDisposed;

  void start(
    Ref ref,
    void Function(AsyncValue<AuthState>? previous, AsyncValue<AuthState> next)
    onChange,
  ) {
    ref.listen<AsyncValue<AuthState>>(authNotifierProvider, (previous, next) {
      if (isDisposed()) return;
      onChange(previous, next);
    });
  }

  void dispose() {}
}
