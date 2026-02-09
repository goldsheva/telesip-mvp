import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class AudioFocusService {
  AudioFocusService._();

  static const MethodChannel _channel = MethodChannel(
    'app.calls/notifications',
  );

  static Future<void> acquire({required String callId}) async {
    try {
      debugPrint('[AUDIO_FOCUS] acquire callId=$callId');
      await _channel.invokeMethod('acquireAudioFocus', <String, dynamic>{
        'callId': callId,
      });
    } catch (error) {
      debugPrint('[AUDIO_FOCUS] acquire failed: $error');
    }
  }

  static Future<void> release() async {
    try {
      debugPrint('[AUDIO_FOCUS] release');
      await _channel.invokeMethod('releaseAudioFocus');
    } catch (error) {
      debugPrint('[AUDIO_FOCUS] release failed: $error');
    }
  }
}
