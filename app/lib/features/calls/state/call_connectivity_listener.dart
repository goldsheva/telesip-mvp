import 'dart:async';

import 'package:app/services/network_connectivity_service.dart';

class CallConnectivityListener {
  CallConnectivityListener({
    required this.connectivityService,
    required this.isDisposed,
    required this.onOnlineChanged,
    required this.onInitialOnlineResolved,
    required this.logSnapshot,
  });

  final NetworkConnectivityService connectivityService;
  final bool Function() isDisposed;
  final void Function(bool online) onOnlineChanged;
  final void Function(bool online) onInitialOnlineResolved;
  final void Function(String tag) logSnapshot;

  StreamSubscription<bool>? _subscription;
  bool _started = false;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    _subscription = connectivityService.onOnlineChanged.listen((online) {
      if (isDisposed()) return;
      onOnlineChanged(online);
    });
    final online = await connectivityService.isOnline();
    if (isDisposed()) return;
    onInitialOnlineResolved(online);
    logSnapshot('connectivity-init');
  }

  void dispose() {
    _subscription?.cancel();
    _subscription = null;
  }
}
