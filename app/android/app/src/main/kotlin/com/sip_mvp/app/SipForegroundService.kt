package com.sip_mvp.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

class SipForegroundService : Service() {
  companion object {
    const val ACTION_START = "app.sip.FGS_START"
    const val ACTION_STOP = "app.sip.FGS_STOP"
    private const val CHANNEL_ID = "sip_foreground"
    private const val CHANNEL_NAME = "SIP service"
    private const val NOTIF_ID = 101
  }

  override fun onCreate() {
    super.onCreate()
    createNotificationChannel()
  }

  override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
    when (intent?.action) {
      ACTION_START -> {
        startForeground(NOTIF_ID, buildNotification())
        return START_STICKY
      }
      ACTION_STOP -> {
        stopForeground(true)
        stopSelf()
        return START_NOT_STICKY
      }
      else -> return START_STICKY
    }
  }

  override fun onDestroy() {
    stopForeground(true)
    super.onDestroy()
  }

  override fun onBind(intent: Intent?): IBinder? = null

  private fun createNotificationChannel() {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
    val manager = getSystemService(NotificationManager::class.java)
    val existing = manager?.getNotificationChannel(CHANNEL_ID)
    if (existing != null) return
    val channel = NotificationChannel(CHANNEL_ID, CHANNEL_NAME, NotificationManager.IMPORTANCE_LOW)
    channel.setSound(null, null)
    channel.enableVibration(false)
    channel.setShowBadge(false)
    manager?.createNotificationChannel(channel)
  }

  private fun buildNotification(): Notification {
    return NotificationCompat.Builder(this, CHANNEL_ID)
        .setContentTitle("SIP service active")
        .setContentText("Ready to receive calls")
        .setSmallIcon(R.mipmap.ic_launcher)
        .setOngoing(true)
        .setOnlyAlertOnce(true)
        .setPriority(NotificationCompat.PRIORITY_LOW)
        .build()
  }
}
