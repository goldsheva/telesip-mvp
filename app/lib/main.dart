import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:app/app.dart';
import 'package:app/config/env_config.dart';
import 'package:app/features/fcm/providers.dart';
import 'package:app/platform/foreground_service.dart';
import 'package:app/services/firebase_messaging_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  EnvConfig.init(Environment.prod);
  unawaited(ForegroundService.startForegroundService());

  final container = ProviderContainer();
  await FirebaseMessagingService.initialize(
    onTokenChanged: (token) =>
        container.read(fcmTokenRegistrarProvider).register(token),
  );

  runApp(UncontrolledProviderScope(container: container, child: const App()));
}
