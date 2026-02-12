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
  private const val DEBUG_CHANNEL_ID = "incoming_calls_debug"
  private const val DEBUG_CHANNEL_NAME = "Incoming Calls (Debug)"
  internal const val NOTIFICATION_ID = 424242
  private const val RELEASE_CHANNEL_ID = "incoming_calls"
  private const val RELEASE_CHANNEL_NAME = "Incoming Calls"
  private const val RELEASE_NOTIFICATION_ID = 424241
  private const val DEBUG_ACTION_RECEIVER =
    "com.sip_mvp.app.DebugIncomingActionReceiver"

  fun showDebugNotification(
    context: Context,
    callId: String?,
    from: String?,
  ) {
    val applicationContext = context.applicationContext
    ensureDebugChannel(applicationContext)

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

    val builder = NotificationCompat.Builder(applicationContext, CHANNEL_ID)
      .setSmallIcon(applicationContext.applicationInfo.icon)
      .setContentTitle("Incoming call (debug)")
      .setContentText(composeContentText(callId, from))
      .setCategory(NotificationCompat.CATEGORY_CALL)
      .setPriority(NotificationCompat.PRIORITY_HIGH)
      .setAutoCancel(true)
      .setContentIntent(tapPendingIntent)

    if (BuildConfig.DEBUG) {
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
      if (answerPendingIntent != null) {
        builder.addAction(
          NotificationCompat.Action.Builder(
            android.R.drawable.ic_menu_call,
            "Answer",
            answerPendingIntent,
          ).build(),
        )
      }
      if (declinePendingIntent != null) {
        builder.addAction(
          NotificationCompat.Action.Builder(
            android.R.drawable.ic_menu_close_clear_cancel,
            "Decline",
            declinePendingIntent,
          ).build(),
        )
      }
    }

    NotificationManagerCompat.from(applicationContext).notify(NOTIFICATION_ID, builder.build())
    CallLog.d("DebugIncomingHint", "Debug incoming notification posted id=$NOTIFICATION_ID")
  }

  fun cancelDebugNotification(context: Context) {
    NotificationManagerCompat.from(context.applicationContext).cancel(NOTIFICATION_ID)
  }

  fun showIncomingNotification(
    context: Context,
    callId: String?,
    from: String?,
  ) {
    val applicationContext = context.applicationContext
    ensureReleaseChannel(applicationContext)

    val tapIntent = Intent(applicationContext, MainActivity::class.java).apply {
      putExtra(MainActivity.EXTRA_CHECK_PENDING_HINT, true)
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

    val builder = NotificationCompat.Builder(applicationContext, RELEASE_CHANNEL_ID)
      .setSmallIcon(applicationContext.applicationInfo.icon)
      .setContentTitle("Incoming call")
      .setContentText(composeContentText(callId, from))
      .setCategory(NotificationCompat.CATEGORY_CALL)
      .setPriority(NotificationCompat.PRIORITY_HIGH)
      .setAutoCancel(true)
      .setContentIntent(tapPendingIntent)

    if (callId != null) {
      builder.addAction(
        NotificationCompat.Action.Builder(
          android.R.drawable.ic_menu_call,
          "Answer",
          buildReleaseActionPendingIntent(
            applicationContext,
            IncomingActionReceiver.ACTION_INCOMING_ANSWER,
            requestCode = 11,
            callId = callId,
          ),
        ).build(),
      )
      builder.addAction(
        NotificationCompat.Action.Builder(
          android.R.drawable.ic_menu_close_clear_cancel,
          "Decline",
          buildReleaseActionPendingIntent(
            applicationContext,
            IncomingActionReceiver.ACTION_INCOMING_DECLINE,
            requestCode = 12,
            callId = callId,
          ),
        ).build(),
      )
    }

    NotificationManagerCompat.from(applicationContext)
      .notify(RELEASE_NOTIFICATION_ID, builder.build())
    CallLog.d("IncomingHint", "Release incoming notification posted id=$RELEASE_NOTIFICATION_ID")
  }

  fun cancelIncomingNotification(context: Context) {
    NotificationManagerCompat.from(context.applicationContext)
      .cancel(RELEASE_NOTIFICATION_ID)
  }

  private fun composeContentText(callId: String?, from: String?): String {
    return when {
      callId != null && from != null -> "Call $callId from $from"
      callId != null -> "Call $callId"
      from != null -> "Call from $from"
      else -> "Tap to open"
    }
  }

  private fun buildActionPendingIntent(
    context: Context,
    action: String,
    requestCode: Int,
    callId: String?,
  ): PendingIntent? {
    if (!BuildConfig.DEBUG) return null
    val intent = Intent().apply {
      this.action = action
      setClassName(context.packageName, DEBUG_ACTION_RECEIVER)
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

  private fun buildReleaseActionPendingIntent(
    context: Context,
    action: String,
    requestCode: Int,
    callId: String,
  ): PendingIntent {
    val intent = Intent(context, IncomingActionReceiver::class.java).apply {
      this.action = action
      putExtra(IncomingActionReceiver.EXTRA_CALL_ID, callId)
    }
    return PendingIntent.getBroadcast(
      context,
      requestCode,
      intent,
      PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
    )
  }

  private fun ensureDebugChannel(context: Context) {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
    val manager = context.getSystemService(NotificationManager::class.java) ?: return
    val existing = manager.getNotificationChannel(DEBUG_CHANNEL_ID)
    if (existing != null) return
    val channel = NotificationChannel(
      DEBUG_CHANNEL_ID,
      DEBUG_CHANNEL_NAME,
      NotificationManager.IMPORTANCE_HIGH,
    ).apply {
      description = "Debug incoming call notifications"
    }
    manager.createNotificationChannel(channel)
  }

  private fun ensureReleaseChannel(context: Context) {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
    val manager = context.getSystemService(NotificationManager::class.java) ?: return
    val existing = manager.getNotificationChannel(RELEASE_CHANNEL_ID)
    if (existing != null) return
    val channel = NotificationChannel(
      RELEASE_CHANNEL_ID,
      RELEASE_CHANNEL_NAME,
      NotificationManager.IMPORTANCE_HIGH,
    ).apply {
      description = "Incoming call notifications"
    }
    manager.createNotificationChannel(channel)
  }
}
