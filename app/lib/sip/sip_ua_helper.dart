import 'package:sip_ua/sip_ua.dart' show SIPUAHelper, UaSettings;

class AppSipUaHelper extends SIPUAHelper {
  bool _started = false;

  @override
  Future<void> start(UaSettings uaSettings) async {
    await super.start(uaSettings);
    _started = true;
  }

  @override
  void stop() {
    if (!_started) return;
    try {
      super.stop();
    } catch (_) {
      // best-effort
    } finally {
      _started = false;
    }
  }
}
