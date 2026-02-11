package com.sip_mvp.app

import android.app.KeyguardManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat

object NotificationHelper {
  private const val CHANNEL_ID = "calls"
  private const val CHANNEL_NAME = "Calls"

  fun ensureChannel(context: Context, notificationManager: NotificationManager) {
    if (notificationManager.getNotificationChannel(CHANNEL_ID) != null) {
      return
    }
    val channel = NotificationChannel(
      CHANNEL_ID,
      CHANNEL_NAME,
      NotificationManager.IMPORTANCE_HIGH
    ).apply {
      description = "Incoming call alerts"
      enableVibration(true)
      lockscreenVisibility = NotificationCompat.VISIBILITY_PUBLIC
    }
    notificationManager.createNotificationChannel(channel)
  }

  fun showIncoming(
    context: Context,
    notificationManager: NotificationManager,
    callId: String,
    from: String,
    displayName: String?
  ) {
    ensureChannel(context, notificationManager)
    val incomingIntent = Intent(context, IncomingCallActivity::class.java).apply {
      putExtra("call_id", callId)
      putExtra("from", from)
      putExtra("display_name", displayName)
      action = "open_incoming"
      addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
    }
    val baseId = getNotificationId(callId)
    val fullScreenIntent = PendingIntent.getActivity(
      context,
      reqCode(baseId, 0),
      incomingIntent,
      PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
    )
    val contentIntent = PendingIntent.getActivity(
      context,
      reqCode(baseId, 1),
      mainIntent(context, callId, from, displayName),
      PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
    )
    val answerIntent = PendingIntent.getBroadcast(
      context,
      reqCode(baseId, 2),
      Intent(CallActionReceiver.ACTION_ANSWER).apply {
        putExtra("call_id", callId)
      },
      PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
    )
    val declineIntent = PendingIntent.getBroadcast(
      context,
      reqCode(baseId, 3),
      Intent(CallActionReceiver.ACTION_DECLINE).apply {
        putExtra("call_id", callId)
      },
      PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
    )
    val builder = NotificationCompat.Builder(context, CHANNEL_ID)
      .setContentTitle(displayName ?: "Incoming call")
      .setContentText("From $from")
      .setSmallIcon(R.mipmap.ic_launcher)
      .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
      .setPriority(NotificationCompat.PRIORITY_HIGH)
      .setCategory(NotificationCompat.CATEGORY_CALL)
      .setDefaults(NotificationCompat.DEFAULT_ALL)
      .setOngoing(true)
      .apply {
        if (shouldUseFullScreenIntent(context)) {
          setFullScreenIntent(fullScreenIntent, true)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
          setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
        }
      }
      .setContentIntent(contentIntent)
      .addAction(android.R.drawable.ic_menu_call, "Answer", answerIntent)
      .addAction(android.R.drawable.ic_menu_close_clear_cancel, "Decline", declineIntent)

    notificationManager.notify(getNotificationId(callId), builder.build())
  }

  private fun mainIntent(context: Context, callId: String, from: String, displayName: String?): Intent {
    return Intent(context, MainActivity::class.java).apply {
      putExtra("call_id", callId)
      putExtra("action", "open_incoming")
      putExtra("from", from)
      putExtra("display_name", displayName)
      addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
    }
  }

  private fun shouldUseFullScreenIntent(context: Context): Boolean {
    val keyguardManager =
      context.getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager
    return keyguardManager?.isKeyguardLocked ?: true
  }

  fun cancel(notificationManager: NotificationManager, callId: String) {
    notificationManager.cancel(getNotificationId(callId))
  }

  private fun getNotificationId(callId: String): Int {
    return callId.hashCode() and 0x7fffffff
  }

  private fun reqCode(baseId: Int, offset: Int): Int {
    return (baseId + offset) and 0x7fffffff
  }
}
