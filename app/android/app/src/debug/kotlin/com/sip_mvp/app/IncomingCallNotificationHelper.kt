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
  private const val NOTIFICATION_ID = 424242

  fun showDebugNotification(context: Context) {
    val applicationContext = context.applicationContext
    ensureChannel(applicationContext)

    val intent = Intent(applicationContext, MainActivity::class.java).apply {
      putExtra(MainActivity.EXTRA_DEBUG_CHECK_PENDING_HINT, true)
      putExtra("from_incoming_notification", true)
      addFlags(
        Intent.FLAG_ACTIVITY_NEW_TASK or
          Intent.FLAG_ACTIVITY_SINGLE_TOP or
          Intent.FLAG_ACTIVITY_CLEAR_TOP,
      )
    }
    val pendingIntent = PendingIntent.getActivity(
      applicationContext,
      0,
      intent,
      PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
    )

    val builder = NotificationCompat.Builder(applicationContext, CHANNEL_ID)
      .setSmallIcon(applicationContext.applicationInfo.icon)
      .setContentTitle("Incoming call (debug)")
      .setContentText("Tap to open")
      .setCategory(NotificationCompat.CATEGORY_CALL)
      .setPriority(NotificationCompat.PRIORITY_HIGH)
      .setAutoCancel(true)
      .setContentIntent(pendingIntent)

    NotificationManagerCompat.from(applicationContext).notify(NOTIFICATION_ID, builder.build())
    CallLog.d("DebugIncomingHint", "Debug incoming notification posted id=$NOTIFICATION_ID")
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
