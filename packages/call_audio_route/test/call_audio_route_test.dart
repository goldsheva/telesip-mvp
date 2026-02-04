import 'package:flutter_test/flutter_test.dart';
import 'package:call_audio_route/call_audio_route.dart';
import 'package:call_audio_route/call_audio_route_platform_interface.dart';
import 'package:call_audio_route/call_audio_route_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockCallAudioRoutePlatform
    with MockPlatformInterfaceMixin
    implements CallAudioRoutePlatform {

  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final CallAudioRoutePlatform initialPlatform = CallAudioRoutePlatform.instance;

  test('$MethodChannelCallAudioRoute is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelCallAudioRoute>());
  });

  test('getPlatformVersion', () async {
    CallAudioRoute callAudioRoutePlugin = CallAudioRoute();
    MockCallAudioRoutePlatform fakePlatform = MockCallAudioRoutePlatform();
    CallAudioRoutePlatform.instance = fakePlatform;

    expect(await callAudioRoutePlugin.getPlatformVersion(), '42');
  });
}
