import 'package:flutter/foundation.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'call_audio_route_method_channel.dart';
import 'src/audio_route_info.dart';

/// Platform interface that backs the Dart API.
abstract class CallAudioRoutePlatform extends PlatformInterface {
  CallAudioRoutePlatform() : super(token: _token);

  static final Object _token = Object();

  static CallAudioRoutePlatform _instance = MethodChannelCallAudioRoute();

  /// The default instance that uses method channels.
  static CallAudioRoutePlatform get instance => _instance;

  /// Platforms should set this when they implement the interface.
  static set instance(CallAudioRoutePlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<void> setRoute(AudioRoute route);

  Future<AudioRouteInfo> getRouteInfo();

  Stream<AudioRouteInfo> get routeChanges;

  Future<void> configureForCall();

  Future<void> stopCallAudio();
}
