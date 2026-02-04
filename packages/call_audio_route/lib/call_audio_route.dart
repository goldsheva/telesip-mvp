library call_audio_route;

export 'src/audio_route_info.dart';

import 'call_audio_route_platform_interface.dart';

/// Entry point for the plugin.
class CallAudioRoute {
  /// Routes the audio stream to the requested target.
  Future<void> setRoute(AudioRoute route) => CallAudioRoutePlatform.instance.setRoute(route);

  /// Returns the current routing state.
  Future<AudioRouteInfo> getRouteInfo() => CallAudioRoutePlatform.instance.getRouteInfo();

  /// Fires whenever the native layer detects a route change.
  Stream<AudioRouteInfo> get routeChanges => CallAudioRoutePlatform.instance.routeChanges;
}
