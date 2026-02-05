import 'package:flutter_test/flutter_test.dart';
import 'package:call_audio_route/call_audio_route.dart';
import 'package:call_audio_route/call_audio_route_platform_interface.dart';
import 'package:call_audio_route/call_audio_route_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockCallAudioRoutePlatform
    with MockPlatformInterfaceMixin
    implements CallAudioRoutePlatform {
  @override
  Future<void> configureForCall() async {}

  @override
  Future<AudioRouteInfo> getRouteInfo() async => const AudioRouteInfo(
    current: AudioRoute.systemDefault,
    available: [AudioRoute.systemDefault],
    bluetoothConnected: false,
    wiredConnected: false,
  );

  @override
  Stream<AudioRouteInfo> get routeChanges => const Stream.empty();

  @override
  Future<void> setRoute(AudioRoute route) async {}

  @override
  Future<void> stopCallAudio() async {}
}

void main() {
  final CallAudioRoutePlatform initialPlatform =
      CallAudioRoutePlatform.instance;

  tearDown(() {
    CallAudioRoutePlatform.instance = initialPlatform;
  });

  test('$MethodChannelCallAudioRoute is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelCallAudioRoute>());
  });

  test('getRouteInfo forwards to platform', () async {
    final CallAudioRoute callAudioRoutePlugin = CallAudioRoute();
    final MockCallAudioRoutePlatform fakePlatform =
        MockCallAudioRoutePlatform();
    CallAudioRoutePlatform.instance = fakePlatform;

    final info = await callAudioRoutePlugin.getRouteInfo();
    expect(info.current, AudioRoute.systemDefault);
  });
}
