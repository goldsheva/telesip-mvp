# Debugging Incoming Hint & Notification Actions

## Send a pending incoming hint (debug build)
```bash
adb shell am broadcast \
  -a com.sip_mvp.app.DEBUG_PENDING_INCOMING_HINT \
  --es payload '{"type":"incoming_call","call_id":"adb123","from":"ADB Tester","display_name":"ADB"}' \
  --ez trigger_ui true
```

## Simulate a cancel/end event (release path)
Send an FCM-style payload that mirrors the server cancel keys to the device/token you want to test:
```bash
curl -X POST https://fcm.googleapis.com/fcm/send \
  -H "Authorization: key=<YOUR_FCM_SERVER_KEY>" \
  -H "Content-Type: application/json" \
  -d '{
    "to": "<DEVICE_TOKEN>",
    "data": {
      "type": "call_cancelled",
      "call_id": "adb123"
    }
  }'
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

## E2E Answer from notification (debug)
1. Send a pending hint (e.g. the debug broadcast above or a release FCM `type":"incoming_call"` payload) so the release notification can appear.
2. Open the app, long-press the top title to show the debug dialog, then tap **Run incoming debug flow**. This will refresh the release notification, run `callNotifier.runIncomingPipeline("manual-debug")`, and print a pending action dump line to logcat.
3. While the release notification is visible, simulate tapping Answer (or tap it manually). To fake it from adb:
```bash
adb shell am broadcast \
  -a com.sip_mvp.app.action.INCOMING_ANSWER \
  --es call_id "adb123"
```

Watch logcat for these tags (filter by `IncomingHint`/`[CALLS]`):
- `IncomingHint: pending hint persisted notificationPosted=... callId=adb123`
- `IncomingHint: Release incoming notification posted id=424241` (and `... actions attached callId=adb123`)
- `[CALLS] pending action dump manual-debug pendingCount=1 lastAction={...}`
- `IncomingHint: Stored pending action source=notification_action type=answer callId=adb123 ts=... enqueued=true`

These lines ensure the release notification was posted, the manual debug flow triggered, and the notification action was persisted for the engine to consume.

Watch for logs:
- `PendingCallActionStore`: enqueued/suppressed pending actions
- `[CALLS] drainPendingCallActions ...`: drain summary + applied actions
