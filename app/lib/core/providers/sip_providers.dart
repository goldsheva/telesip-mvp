import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:app/sip/sip_engine.dart';

final sipEngineProvider = Provider<SipEngine>((ref) {
  final engine = SipUaEngine();
  ref.onDispose(engine.dispose);
  return engine;
});

final sipEventsProvider = StreamProvider<SipEvent>((ref) {
  final engine = ref.watch(sipEngineProvider);
  return engine.events;
});
