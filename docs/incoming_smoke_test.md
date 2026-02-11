## Incoming Call Smoke Checklist

Each step lists the device state, what UI/logs to expect, and the pass/fail condition.

1. **Unlocked screen only**
   - Device: unlocked (no full-screen), optionally DND off.
   - Behavior: incoming notification appears (no full-screen overlay), notification is ongoing.
   - Logs:
     * `NotificationHelper`: `notify baseId=... from=... keyguardLocked=false ...`
     * `[CALLS_NOTIF] showIncoming callId=... callUuid=...`
     * On tap, `CallActionReceiver`: `action_enqueued ... duplicateSuppressed=false`.
     * Dart `[CALLS] drainPendingCallActions summary ...`
   - Pass: Notification disappears with a single action, log line confirms action and drain summary.

2. **Locked screen**
   - Device: screen locked (keyguard), possibly DND off.
   - Behavior: full-screen incoming intent appears, notification remains ongoing while ringing.
   - Logs:
     * `NotificationHelper`: `notify ... keyguardLocked=true ...`
     * `CallActionReceiver`: action enqueued line + `[CALLS_NOTIF] updateNotRinging ...` if any.
   - Pass: Full-screen shown, Answer/Decline collapse notification and `notification cancel` log fires.

3. **Double-tap same action**
   - Device: any state.
   - Behavior: tap Answer (or Decline) twice quickly.
   - Logs:
     * Second tap should record `duplicateSuppressed=true` in `CallActionReceiver`.
     * Only one `[CALLS] drainPendingCallActions summary` should show an action processed.
   - Pass: Only single action is enqueued/processed even though two taps occurred.

4. **Duplicate FCM/RPC within 2 seconds**
   - Device: same incoming call, simulate stalled Flutter by re-sending incoming payload <2s later.
   - Behavior: Native `NotificationHelper` logs `incoming suppressed call_id=... call_uuid=...` and no new notification reinstates.
   - Pass: No additional notification after suppression log.

5. **Dart drain summary verification**
   - Trigger any action (Answer or Decline) from notification.
   - Logs: look for `[CALLS] drainPendingCallActions summary total=... processed=... dedupSkipped=... unknownCleared=...`.
   - Pass: Summary line present with processed>0 and unknownCleared reflecting cleanup.
