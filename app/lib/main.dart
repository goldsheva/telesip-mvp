import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app/app.dart';
import 'package:app/config/env_config.dart';
import 'package:app/services/firebase_messaging_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  EnvConfig.init(Environment.prod);
  await FirebaseMessagingService.initialize();

  runApp(const ProviderScope(child: App()));
}
