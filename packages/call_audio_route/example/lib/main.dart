import 'dart:async';

import 'package:call_audio_route/call_audio_route.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final _router = CallAudioRoute();
  AudioRouteInfo? _info;
  late final StreamSubscription<AudioRouteInfo> _subscription;

  @override
  void initState() {
    super.initState();
    _subscription = _router.routeChanges.listen((event) {
      setState(() {
        _info = event;
      });
    });
    _router.getRouteInfo().then((value) {
      setState(() {
        _info = value;
      });
    });
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }

  Future<void> _setRoute(AudioRoute route) async {
    await _router.setRoute(route);
  }

  Future<void> _simulateIncomingCall() => _setRoute(AudioRoute.earpiece);
  Future<void> _simulateAnswer() => _setRoute(AudioRoute.speaker);
  Future<void> _simulateHangup() => _setRoute(AudioRoute.systemDefault);

  @override
  Widget build(BuildContext context) {
    final currentRoute = _info?.current.name ?? 'unknown';
    final availableRoutes = _info?.available.map((it) => it.name).join(', ') ?? 'waiting...';
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('call_audio_route example'),
        ),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Current route: $currentRoute'),
              const SizedBox(height: 8),
              Text('Available routes: $availableRoutes'),
              const SizedBox(height: 8),
              Text('Bluetooth connected: ${_info?.bluetoothConnected ?? false}'),
              Text('Wired connected: ${_info?.wiredConnected ?? false}'),
              const SizedBox(height: 24),
              Text('Call lifecycle helpers'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  ElevatedButton(
                    onPressed: _simulateIncomingCall,
                    child: const Text('Incoming call (earpiece)'),
                  ),
                  ElevatedButton(
                    onPressed: _simulateAnswer,
                    child: const Text('Answer (speaker)'),
                  ),
                  ElevatedButton(
                    onPressed: _simulateHangup,
                    child: const Text('Hangup (system default)'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text('Direct route switches'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  ElevatedButton(
                    onPressed: () => _setRoute(AudioRoute.bluetooth),
                    child: const Text('Bluetooth'),
                  ),
                  ElevatedButton(
                    onPressed: () => _setRoute(AudioRoute.wiredHeadset),
                    child: const Text('Wired headset'),
                  ),
                  ElevatedButton(
                    onPressed: () => _setRoute(AudioRoute.speaker),
                    child: const Text('Speaker'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
