## Incoming Call Smoke Checklist

1. **Unlocked screen** – show incoming notification only (no full-screen); tapping Answer/Decline removes it instantly and logs the `notification cancel`/`answerFromNotification` or `declineFromNotification` trace.
2. **Locked screen** – full-screen intent fires, the notification stays visible while ringing, and Answer/Decline collapse it while logging the `notification cancel` and `action_enqueued` markers.
3. **Double tap on the same action** – verify only one pending action is recorded (`duplicateSuppressed=true` in `CallActionReceiver` log) and the Dart drain summary still processes once.
4. **Duplicate FCM within ~2 seconds** – `NotificationHelper` should log `incoming suppressed` (based on the suppression map) and no new notification should pop up.
5. **Dart drain summary** – after handling a notification action, check for the summary line `[CALLS] drainPendingCallActions summary ...` to confirm processed/dedup/unknown counts.
