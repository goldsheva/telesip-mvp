# Native audio routing integration

Use the built-in `AudioRouteService` (_app.calls/audio_route_) for reliable speaker/earpiece/Bluetooth routing inside the Flutter app.

1. Plug it into the call lifecycle from wherever you manage calls:

```dart
Future<void> onIncomingCall() async {
  await AudioRouteService.setRoute(AudioRoute.earpiece);
}

Future<void> onAnswer() async {
  await AudioRouteService.setRoute(AudioRoute.speaker);
}

Future<void> onCallReconnect() async {
  final info = await AudioRouteService.getRouteInfo();
  if (info?.bluetoothConnected == true) {
    await AudioRouteService.setRoute(AudioRoute.bluetooth);
  } else if (info != null) {
    await AudioRouteService.setRoute(info.current);
  }
}

Future<void> onHangup() async {
  await AudioRouteService.setRoute(AudioRoute.systemDefault);
}
```

2. Listen to `routeChanges` if you need to react when accessories connect/disconnect:

```dart
AudioRouteService.routeChanges().listen((info) {
  // update UI, show “Bluetooth disconnected”, etc.
});
```

The service keeps the native audio session in `MODE_IN_COMMUNICATION`, ensures focus is requested/abandoned, and lets you switch between speaker, earpiece, Bluetooth, or wired headsets without duplicating the SIP layer logic.
