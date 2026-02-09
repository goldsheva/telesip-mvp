package com.sip_mvp.app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
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
    val builder = NotificationCompat.Builder(context, CHANNEL_ID)
      .setContentTitle(displayName ?: "Incoming call")
      .setContentText("From $from")
      .setSmallIcon(R.mipmap.ic_launcher)
      .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
      .setPriority(NotificationCompat.PRIORITY_HIGH)
      .setCategory(NotificationCompat.CATEGORY_CALL)
      .setAutoCancel(true)
      .setDefaults(NotificationCompat.DEFAULT_ALL)

    notificationManager.notify(getNotificationId(callId), builder.build())
  }

  fun cancel(notificationManager: NotificationManager, callId: String) {
    notificationManager.cancel(getNotificationId(callId))
  }

  private fun getNotificationId(callId: String): Int {
    return callId.hashCode() and 0x7fffffff
  }
}
