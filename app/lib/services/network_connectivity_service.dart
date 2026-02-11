import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

class NetworkConnectivityService {
  NetworkConnectivityService()
    : _onlineStream = _connectivity.onConnectivityChanged
          .map(_isOnlineFromResults)
          .asBroadcastStream();

  static final Connectivity _connectivity = Connectivity();

  final Stream<bool> _onlineStream;

  Stream<bool> get onOnlineChanged => _onlineStream;

  Future<bool> isOnline() async {
    final results = await _connectivity.checkConnectivity();
    return _isOnlineFromResults(results);
  }

  static bool _isOnlineFromResults(List<ConnectivityResult> results) {
    return results.any((result) => result != ConnectivityResult.none);
  }
}
