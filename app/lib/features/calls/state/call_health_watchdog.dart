import 'dart:async';

class CallHealthWatchdog {
  CallHealthWatchdog({
    required this.isDisposed,
    required this.interval,
    required this.onTick,
  });

  final bool Function() isDisposed;
  final Duration interval;
  final void Function() onTick;

  Timer? _timer;

  bool get isRunning => _timer != null;

  void start() {
    if (isRunning) return;
    _timer = Timer.periodic(interval, (_) {
      if (isDisposed()) return;
      onTick();
    });
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }
}
