package com.sip_mvp.app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat

object IncomingCallNotificationHelper {
  private const val CHANNEL_ID = "incoming_calls_debug"
  private const val CHANNEL_NAME = "Incoming Calls (Debug)"
  internal const val NOTIFICATION_ID = 424242

  fun showDebugNotification(
    context: Context,
    callId: String?,
    from: String?,
  ) {
    val applicationContext = context.applicationContext
    ensureChannel(applicationContext)

    val tapIntent = Intent(applicationContext, MainActivity::class.java).apply {
      putExtra(MainActivity.EXTRA_DEBUG_CHECK_PENDING_HINT, true)
      putExtra("from_incoming_notification", true)
      addFlags(
        Intent.FLAG_ACTIVITY_NEW_TASK or
          Intent.FLAG_ACTIVITY_SINGLE_TOP or
          Intent.FLAG_ACTIVITY_CLEAR_TOP,
      )
    }
    val tapPendingIntent = PendingIntent.getActivity(
      applicationContext,
      0,
      tapIntent,
      PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
    )

    val answerPendingIntent = buildActionPendingIntent(
      applicationContext,
      DebugIncomingActionReceiver.ACTION_DEBUG_INCOMING_ANSWER,
      requestCode = 1,
      callId = callId,
    )
    val declinePendingIntent = buildActionPendingIntent(
      applicationContext,
      DebugIncomingActionReceiver.ACTION_DEBUG_INCOMING_DECLINE,
      requestCode = 2,
      callId = callId,
    )

    val contentText = when {
      callId != null && from != null -> "Call $callId from $from"
      callId != null -> "Call $callId"
      from != null -> "Call from $from"
      else -> "Tap to open"
    }

    val builder = NotificationCompat.Builder(applicationContext, CHANNEL_ID)
      .setSmallIcon(applicationContext.applicationInfo.icon)
      .setContentTitle("Incoming call (debug)")
      .setContentText(contentText)
      .setCategory(NotificationCompat.CATEGORY_CALL)
      .setPriority(NotificationCompat.PRIORITY_HIGH)
      .setAutoCancel(true)
      .setContentIntent(tapPendingIntent)
      .addAction(
        NotificationCompat.Action.Builder(
          android.R.drawable.ic_menu_call,
          "Answer",
          answerPendingIntent,
        ).build(),
      )
      .addAction(
        NotificationCompat.Action.Builder(
          android.R.drawable.ic_menu_close_clear_cancel,
          "Decline",
          declinePendingIntent,
        ).build(),
      )

    NotificationManagerCompat.from(applicationContext).notify(NOTIFICATION_ID, builder.build())
    CallLog.d("DebugIncomingHint", "Debug incoming notification posted id=$NOTIFICATION_ID")
  }

  fun cancelDebugNotification(context: Context) {
    NotificationManagerCompat.from(context.applicationContext).cancel(NOTIFICATION_ID)
  }

  private fun buildActionPendingIntent(
    context: Context,
    action: String,
    requestCode: Int,
    callId: String?,
  ): PendingIntent {
    val intent = Intent(context, DebugIncomingActionReceiver::class.java).apply {
      this.action = action
      putExtra("source", "incoming_notification")
      if (callId != null) {
        putExtra("call_id", callId)
      }
    }
    return PendingIntent.getBroadcast(
      context,
      requestCode,
      intent,
      PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
    )
  }

  private fun ensureChannel(context: Context) {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
    val manager = context.getSystemService(NotificationManager::class.java) ?: return
    val existing = manager.getNotificationChannel(CHANNEL_ID)
    if (existing != null) return
    val channel = NotificationChannel(
      CHANNEL_ID,
      CHANNEL_NAME,
      NotificationManager.IMPORTANCE_HIGH,
    ).apply {
      description = "Debug incoming call notifications"
    }
    manager.createNotificationChannel(channel)
  }
}
