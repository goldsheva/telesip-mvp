# Native audio routing integration

Use the `call_audio_route` plugin from `packages/call_audio_route` for reliable speaker/earpiece/Bluetooth routing inside the Flutter app.

1. Instantiate the helper in a singleton or call controller:

```dart
final callAudioRoute = CallAudioRoute();
```

2. Hook it into the call lifecycle:

```dart
Future<void> onIncomingCall() async {
  await callAudioRoute.setRoute(AudioRoute.earpiece);
}

Future<void> onAnswer() async {
  await callAudioRoute.setRoute(AudioRoute.speaker);
}

Future<void> onCallReconnect() async {
  final info = await callAudioRoute.getRouteInfo();
  if (info.bluetoothConnected) {
    await callAudioRoute.setRoute(AudioRoute.bluetooth);
  } else {
    await callAudioRoute.setRoute(info.current);
  }
}

Future<void> onHangup() async {
  await callAudioRoute.setRoute(AudioRoute.systemDefault);
}
```

3. Observe the `routeChanges` stream to react when accessories connect/disconnect:

```dart
callAudioRoute.routeChanges.listen((info) {
  // update UI, show “Bluetooth disconnected”, etc.
});
```

This keeps the native audio session in `MODE_IN_COMMUNICATION`, ensures focus is requested/abandoned, and lets you switch between speaker, earpiece, Bluetooth, or wired headsets without rewriting the entire SIP layer.
