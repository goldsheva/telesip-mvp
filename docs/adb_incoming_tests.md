# Debugging Incoming Hint & Notification Actions

## Send a pending incoming hint (debug build)
```bash
adb shell am broadcast \
  -a com.sip_mvp.app.DEBUG_PENDING_INCOMING_HINT \
  --es payload '{"type":"incoming_call","call_id":"adb123","from":"ADB Tester","display_name":"ADB"}' \
  --ez trigger_ui true
```

## Trigger Android-side pending hint persist via Flutter channel (release path)
```bash
adb shell am broadcast \
  -a io.flutter.plugins.flutterbroadcastreceiver \
  --es channel app.storage/native \
  --es method persistPendingIncomingHint \
  --es args '{"timestamp":"2024-01-01T00:00:00Z","payload":{"type":"incoming_call","call_id":"ch123","from":"Channel"}}'
```

## Refresh incoming notification from Flutter
Inside a Flutter `flutter attach` session:
```dart
await IncomingNotificationService.refreshPendingIncomingNotification();
```

Watch for logs:
- `PendingCallActionStore`: enqueued/suppressed pending actions
- `[CALLS] drainPendingCallActions ...`: drain summary + applied actions
