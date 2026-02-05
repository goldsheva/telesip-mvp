import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app/app.dart';
import 'package:app/config/env_config.dart';

void main() {
  EnvConfig.init(Environment.prod);
  runApp(const ProviderScope(child: App()));
}
