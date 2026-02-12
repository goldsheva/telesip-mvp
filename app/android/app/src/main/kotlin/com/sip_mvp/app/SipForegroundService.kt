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
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import com.sip_mvp.app.CallLog

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
      CallLog.w("CALLS_FGS", "onStartCommand: null intent (sticky restart) state(starting=$isStarting wake=${SipWakeLock.isHeld()})")
      isStarting = false
      if (SipWakeLock.isHeld()) {
        SipWakeLock.release()
      }
      return START_STICKY
    }
    when (intent?.action) {
      ACTION_START -> {
        val needsMicrophone = intent.getBooleanExtra(EXTRA_NEEDS_MICROPHONE, false)
        CallLog.d(
          "CALLS_FGS",
          "onStartCommand action=START sdk=${Build.VERSION.SDK_INT} startId=$startId needsMic=$needsMicrophone"
        )
        isStarting = true
        pendingStop = false
        val started = startForegroundCompat(getNotification(), needsMicrophone)
        CallLog.d(
          "CALLS_FGS",
          "onStartCommand action=START needsMic=$needsMicrophone started=$started"
        )
        if (!started) {
          CallLog.e(
            "CALLS_FGS",
            "ACTION_START -> startForeground failed sdk=${Build.VERSION.SDK_INT} startId=$startId needsMic=$needsMicrophone"
          )
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
          CallLog.e("CALLS_FGS", "wake lock acquire failed: $error", error)
          isStarting = false
          pendingStop = false
          stopForegroundSafely()
          stopSelf()
          hasStartedForeground = false
          return START_NOT_STICKY
        }
        isStarting = false
        if (pendingStop) {
          CallLog.d("CALLS_FGS", "ACTION_STOP issued during startup, stopping now")
          pendingStop = false
          stopForegroundSafely()
          if (SipWakeLock.isHeld()) {
            CallLog.d("CALLS_FGS", "wake lock release (pending stop)")
          }
          SipWakeLock.release()
          stopSelf()
          hasStartedForeground = false
          return START_NOT_STICKY
        }
        return START_STICKY
      }
      ACTION_STOP -> {
        CallLog.d("CALLS_FGS", "service stop")
        if (isStarting) {
          CallLog.d("CALLS_FGS", "service stop while starting")
          pendingStop = true
          CallLog.d("CALLS_FGS", "defer STOP until started")
          return START_NOT_STICKY
        }
        stopForegroundSafely()
        isStarting = false
        pendingStop = false
        if (SipWakeLock.isHeld()) {
        CallLog.d("CALLS_FGS", "wake lock release (stop)")
        }
        SipWakeLock.release()
        stopSelf()
        hasStartedForeground = false
        return START_NOT_STICKY
      }
      else -> {
        CallLog.w("CALLS_FGS", "onStartCommand: unknown action ${intent.action}; ignoring")
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
      CallLog.d("CALLS_FGS", "wake lock release (destroy)")
    }
    SipWakeLock.release()
    CallLog.d("CALLS_FGS", "service destroy")
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
      CallLog.d("CALLS_FGS", "startForeground types=0x${types.toString(16)} needsMic=$needsMicrophone")
      startForegroundWithTypes(types, notification)
    } else {
      startForegroundSafe(notification)
    }
    hasStartedForeground = started
    return started
  }

  private fun stopForegroundSafely() {
    try {
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
      CallLog.d("CALLS_FGS", "stopForeground(STOP_FOREGROUND_REMOVE)")
        stopForeground(Service.STOP_FOREGROUND_REMOVE)
      } else {
        CallLog.d("CALLS_FGS", "stopForeground(true)")
        stopForeground(true)
      }
    } catch (error: Throwable) {
      CallLog.e("CALLS_FGS", "stopForeground failed: $error", error)
    }
  }

  private fun startForegroundSafe(notification: Notification): Boolean {
    return try {
      startForeground(NOTIF_ID, notification)
      true
    } catch (error: Throwable) {
      CallLog.e("CALLS_FGS", "startForeground(safe) failed: $error", error)
      false
    }
  }

  private fun buildForegroundServiceTypes(needsMicrophone: Boolean): Int {
    var types = ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
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
      CallLog.e(
        "CALLS_FGS",
        "startForeground types failure ${error::class.java.simpleName}: ${error.message}",
        error
      )
      val fallback = types and ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE.inv()
      if (fallback != types) {
        try {
          startForeground(NOTIF_ID, notification, fallback)
          return true
        } catch (fallbackEx: Throwable) {
          CallLog.e("CALLS_FGS", "fallback startForeground(types=$fallback) failed: $fallbackEx", fallbackEx)
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
