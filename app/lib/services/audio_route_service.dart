import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:call_audio_route/call_audio_route.dart';

class AudioRouteService {
  AudioRouteService._();

  static const MethodChannel _methodChannel = MethodChannel('app.calls/audio_route');
  static const EventChannel _eventChannel = EventChannel('app.calls/audio_route/routeChanged');

  static Future<AudioRouteInfo?> getRouteInfo() async {
    try {
      final result = await _methodChannel.invokeMapMethod<String, dynamic>('getRouteInfo');
      if (result == null) return null;
      return AudioRouteInfo.fromMap(result);
    } catch (error) {
      debugPrint('[AUDIO_ROUTE] getRouteInfo failed: $error');
      return null;
    }
  }

  static Future<void> setRoute(AudioRoute route) async {
    try {
      await _methodChannel.invokeMethod('setRoute', <String, dynamic>{
        'route': route.name,
      });
    } catch (error) {
      debugPrint('[AUDIO_ROUTE] setRoute failed: $error');
    }
  }

  static Stream<AudioRouteInfo> routeChanges() {
    return _eventChannel.receiveBroadcastStream().map((event) {
      final map = Map<String, dynamic>.from(event as Map);
      return AudioRouteInfo.fromMap(map);
    }).handleError((error) {
      debugPrint('[AUDIO_ROUTE] routeChanges error: $error');
    });
  }

  static Future<void> startBluetoothSco() async {
    try {
      await _methodChannel.invokeMethod('startBluetoothSco');
    } catch (error) {
      debugPrint('[AUDIO_ROUTE] startBluetoothSco failed: $error');
    }
  }

  static Future<void> stopBluetoothSco() async {
    try {
      await _methodChannel.invokeMethod('stopBluetoothSco');
    } catch (error) {
      debugPrint('[AUDIO_ROUTE] stopBluetoothSco failed: $error');
    }
  }
}
