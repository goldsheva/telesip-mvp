import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:app/sip/sip_engine.dart';

const _usePjsip = bool.fromEnvironment('USE_PJSIP', defaultValue: false);

final sipEngineProvider = Provider<SipEngine>((ref) {
  final engine = _usePjsip ? PjsipSipEngine() : FakeSipEngine();
  ref.onDispose(engine.dispose);
  return engine;
});
