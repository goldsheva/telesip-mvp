import 'package:flutter/services.dart';

import 'call_audio_route_platform_interface.dart';
import 'src/audio_route_info.dart';

/// Method-channel implementation of [CallAudioRoutePlatform].
class MethodChannelCallAudioRoute extends CallAudioRoutePlatform {
  static const _methodChannelName = 'call_audio_route/methods';
  static const _eventChannelName = 'call_audio_route/route_changes';

  final MethodChannel _methodChannel = const MethodChannel(_methodChannelName);
  final EventChannel _eventChannel = const EventChannel(_eventChannelName);

  Stream<AudioRouteInfo>? _routeStream;

  @override
  Future<void> setRoute(AudioRoute route) async {
    await _methodChannel.invokeMethod<void>('setRoute', {'route': route.name});
  }

  @override
  Future<AudioRouteInfo> getRouteInfo() async {
    final data = await _methodChannel.invokeMapMethod<String, Object>(
      'getRouteInfo',
    );
    if (data == null) {
      throw PlatformException(
        code: 'null_route_info',
        message: 'Native implementation returned null route info',
      );
    }
    return AudioRouteInfo.fromMap(data);
  }

  @override
  Stream<AudioRouteInfo> get routeChanges =>
      _routeStream ??= _eventChannel.receiveBroadcastStream().map(
        (event) =>
            AudioRouteInfo.fromMap(Map<Object?, Object?>.from(event as Map)),
      );

  @override
  Future<void> configureForCall() async {
    await _methodChannel.invokeMethod<void>('configureForCall');
  }

  @override
  Future<void> stopCallAudio() async {
    await _methodChannel.invokeMethod<void>('stopCallAudio');
  }
}
