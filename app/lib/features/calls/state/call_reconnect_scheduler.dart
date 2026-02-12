import 'dart:async';

import 'call_reconnect.dart';

class CallReconnectScheduler implements CallReconnectSchedulerApi {
  CallReconnectScheduler({
    required this.isDisposed,
    required this.backoffDelays,
  });

  final bool Function() isDisposed;
  final List<Duration> backoffDelays;

  Timer? _reconnectTimer;
  int _backoffIndex = 0;

  @override
  int get backoffIndex => _backoffIndex;
  bool get hasScheduledTimer => _reconnectTimer != null;

  int get currentDelayIndex {
    if (backoffDelays.isEmpty) return 0;
    return _backoffIndex.clamp(0, backoffDelays.length - 1);
  }

  @override
  Duration get currentDelay {
    if (backoffDelays.isEmpty) return Duration.zero;
    return backoffDelays[currentDelayIndex];
  }

  @override
  int get currentAttemptNumber => currentDelayIndex + 1;

  void resetBackoff() {
    _backoffIndex = 0;
  }

  @override
  void cancel() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }

  @override
  void schedule({required String reason, required void Function() onFire}) {
    cancel();
    if (isDisposed()) return;
    final delay = currentDelay;
    _reconnectTimer = Timer(delay, () {
      if (isDisposed()) return;
      onFire();
    });
    if (backoffDelays.isEmpty) {
      _backoffIndex = 0;
    } else {
      _backoffIndex = (_backoffIndex + 1).clamp(0, backoffDelays.length - 1);
    }
  }
}
