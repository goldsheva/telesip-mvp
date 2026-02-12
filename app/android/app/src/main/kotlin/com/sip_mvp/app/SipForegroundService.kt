package com.sip_mvp.app

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat

class SipForegroundService : Service() {
  companion object {
    const val ACTION_START = "app.sip.FGS_START"
    const val ACTION_STOP = "app.sip.FGS_STOP"
    const val EXTRA_NEEDS_MICROPHONE = "needsMicrophone"
    private const val CHANNEL_ID = "sip_foreground"
    private const val CHANNEL_NAME = "SIP service"
    private const val NOTIF_ID = 101
  }

  override fun onCreate() {
    super.onCreate()
    createNotificationChannel()
  }

  private var isStarting = false
  private var hasStartedForeground = false
  private var pendingStop = false

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
        val needsMicrophone = intent.getBooleanExtra(EXTRA_NEEDS_MICROPHONE, false)
        debugLog("service start needsMicrophone=$needsMicrophone")
        isStarting = true
        pendingStop = false
        val started = startForegroundCompat(getNotification(), needsMicrophone)
        if (!started) {
          debugLog("ACTION_START -> startForeground failed, aborting")
          if (SipWakeLock.isHeld()) {
            SipWakeLock.release()
          }
          hasStartedForeground = false
          isStarting = false
          pendingStop = false
          stopSelf()
          return START_NOT_STICKY
        }
        try {
          SipWakeLock.acquire(this)
        } catch (error: Throwable) {
          debugLog("wake lock acquire failed: $error")
          isStarting = false
          pendingStop = false
          stopForegroundSafely()
          stopSelf()
          hasStartedForeground = false
          return START_NOT_STICKY
        }
        isStarting = false
        if (pendingStop) {
          debugLog("ACTION_STOP issued during startup, stopping now")
          pendingStop = false
          stopForegroundSafely()
          if (SipWakeLock.isHeld()) {
            debugLog("wake lock release (pending stop)")
          }
          SipWakeLock.release()
          stopSelf()
          hasStartedForeground = false
          return START_NOT_STICKY
        }
        return START_STICKY
      }
      ACTION_STOP -> {
        debugLog("service stop")
        if (isStarting) {
          debugLog("service stop while starting")
          pendingStop = true
          debugLog("defer STOP until started")
          return START_NOT_STICKY
        }
        stopForegroundSafely()
        isStarting = false
        pendingStop = false
        if (SipWakeLock.isHeld()) {
          debugLog("wake lock release (stop)")
        }
        SipWakeLock.release()
        stopSelf()
        hasStartedForeground = false
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
    pendingStop = false
    hasStartedForeground = false
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

  private fun startForegroundCompat(notification: Notification, needsMicrophone: Boolean): Boolean {
    val started = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
      val types = buildForegroundServiceTypes(needsMicrophone)
      startForegroundWithTypes(types, notification)
    } else {
      startForegroundSafe(notification)
    }
    hasStartedForeground = started
    return started
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

  private fun startForegroundSafe(notification: Notification): Boolean {
    return try {
      startForeground(NOTIF_ID, notification)
      true
    } catch (error: Throwable) {
      debugLog("startForeground(safe) failed: $error")
      false
    }
  }

  private fun buildForegroundServiceTypes(needsMicrophone: Boolean): Int {
    var types = ServiceInfo.FOREGROUND_SERVICE_TYPE_PHONE_CALL or
        ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
    if (needsMicrophone && hasMicrophonePermission()) {
      types = types or ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
    }
    return types
  }

  private fun startForegroundWithTypes(types: Int, notification: Notification): Boolean {
    return try {
      startForeground(NOTIF_ID, notification, types)
      true
    } catch (error: Throwable) {
      debugLog("startForeground(types=$types) failed: $error")
      val fallback = types and ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE.inv()
      if (fallback != types) {
        try {
          startForeground(NOTIF_ID, notification, fallback)
          return true
        } catch (fallbackEx: Throwable) {
          debugLog("fallback startForeground(types=$fallback) failed: $fallbackEx")
        }
      }
      return startForegroundSafe(notification)
    }
  }

  private fun hasMicrophonePermission(): Boolean {
    return ContextCompat.checkSelfPermission(
      this,
      Manifest.permission.RECORD_AUDIO,
    ) == PackageManager.PERMISSION_GRANTED
  }

}
