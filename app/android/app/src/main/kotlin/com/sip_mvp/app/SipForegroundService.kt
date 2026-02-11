package com.sip_mvp.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.util.Log
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

  private var isStarting = false

  override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
    if (intent == null) {
      debugLog("onStartCommand: null intent (sticky restart) state(starting=$isStarting wake=${
          SipWakeLock.isHeld()})")
      isStarting = false
      if (SipWakeLock.isHeld()) {
        SipWakeLock.release()
      }
      return START_STICKY
    }
    when (intent?.action) {
      ACTION_START -> {
        debugLog("service start")
        isStarting = true
        try {
          SipWakeLock.acquire(this)
        } catch (error: Throwable) {
          debugLog("wake lock acquire failed: $error")
          isStarting = false
          return START_NOT_STICKY
        }
        try {
          if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            debugLog("startForeground: types (Q+)")
          } else {
            debugLog("startForeground: no types (<Q)")
          }
          startForeground(
            NOTIF_ID,
            getNotification()
          )
        } catch (t: Throwable) {
          debugLog("startForeground failed: $t")
          SipWakeLock.release()
          isStarting = false
          stopSelf()
          return START_NOT_STICKY
        }
        isStarting = false
        return START_STICKY
      }
      ACTION_STOP -> {
        debugLog("service stop")
        if (isStarting) {
          debugLog("service stop while starting")
        }
        stopForegroundSafely()
        isStarting = false
        if (SipWakeLock.isHeld()) {
          debugLog("wake lock release (stop)")
        }
        SipWakeLock.release()
        stopSelf()
        return START_NOT_STICKY
      }
      else -> {
        debugLog("onStartCommand: unknown action ${intent.action}; ignoring")
        return START_STICKY
      }
    }
  }

  override fun onDestroy() {
    stopForegroundSafely()
    isStarting = false
    if (SipWakeLock.isHeld()) {
      debugLog("wake lock release (destroy)")
    }
    SipWakeLock.release()
    debugLog("service destroy")
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

  private var cachedNotification: Notification? = null

  private fun getNotification(): Notification {
    cachedNotification?.let { return it }
    val notification = NotificationCompat.Builder(this, CHANNEL_ID)
        .setContentTitle("SIP service active")
        .setContentText("Ready to receive calls")
        .setSmallIcon(R.mipmap.ic_launcher)
        .setOngoing(true)
        .setOnlyAlertOnce(true)
        .setPriority(NotificationCompat.PRIORITY_LOW)
        .build()
    cachedNotification = notification
    return notification
  }

  private fun debugLog(message: String) {
    android.util.Log.d("SipForegroundService", message)
  }

  private fun stopForegroundSafely() {
    try {
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
        debugLog("stopForeground(STOP_FOREGROUND_REMOVE)")
        stopForeground(Service.STOP_FOREGROUND_REMOVE)
      } else {
        debugLog("stopForeground(true)")
        stopForeground(true)
      }
    } catch (error: Throwable) {
      debugLog("stopForeground failed: $error")
    }
  }

}
