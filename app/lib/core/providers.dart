import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

export 'providers/storage_providers.dart';
export 'providers/network_providers.dart';

final appLifecycleProvider = StreamProvider<AppLifecycleState>((ref) {
  final controller = StreamController<AppLifecycleState>.broadcast();
  final observer = _AppLifecycleObserver(controller);
  WidgetsBinding.instance.addObserver(observer);
  final initialState =
      WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed;
  controller.add(initialState);

  ref.onDispose(() {
    WidgetsBinding.instance.removeObserver(observer);
    controller.close();
  });

  return controller.stream;
});

class _AppLifecycleObserver extends WidgetsBindingObserver {
  _AppLifecycleObserver(this._controller);

  final StreamController<AppLifecycleState> _controller;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _controller.add(state);
  }
}
