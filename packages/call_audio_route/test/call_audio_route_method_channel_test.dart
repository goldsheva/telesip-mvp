import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:call_audio_route/call_audio_route_method_channel.dart';
import 'package:call_audio_route/src/audio_route_info.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  MethodChannelCallAudioRoute platform = MethodChannelCallAudioRoute();
  const MethodChannel channel = MethodChannel('call_audio_route/methods');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
          if (methodCall.method == 'getRouteInfo') {
            return <String, Object?>{
              'current': 'systemDefault',
              'available': ['systemDefault'],
              'bluetoothConnected': false,
              'wiredConnected': false,
            };
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('getRouteInfo', () async {
    final info = await platform.getRouteInfo();
    expect(info.current, AudioRoute.systemDefault);
    expect(info.available, contains(AudioRoute.systemDefault));
  });
}
