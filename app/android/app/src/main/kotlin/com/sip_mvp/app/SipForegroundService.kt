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
    const val EXTRA_CALL_ID = "call_id"
    const val EXTRA_CALL_FROM = "call_from"
    const val EXTRA_DISPLAY_NAME = "display_name"
    const val EXTRA_CALL_UUID = "call_uuid"
    const val EXTRA_IS_RINGING = "isRinging"
    private const val CHANNEL_ID = "sip_foreground"
    private const val CHANNEL_NAME = "SIP service"
    const val NOTIF_ID = 101
  }

  override fun onCreate() {
    super.onCreate()
    CallLog.ensureInit(this)
    createNotificationChannel()
  }

  private var isStarting = false
  private var hasStartedForeground = false
  private var currentNotifId: Int = NOTIF_ID
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
        val callId = intent.getStringExtra(EXTRA_CALL_ID)
        val from = intent.getStringExtra(EXTRA_CALL_FROM)
        val displayName = intent.getStringExtra(EXTRA_DISPLAY_NAME)
        val callUuid = intent.getStringExtra(EXTRA_CALL_UUID)
        val isIncomingRinging = intent.getBooleanExtra(EXTRA_IS_RINGING, false)
        val incomingCallId = callId?.takeIf { it.isNotBlank() }
        val incomingFrom = from?.takeIf { it.isNotBlank() }
        val isIncomingCall = incomingCallId != null && incomingFrom != null && isIncomingRinging
        CallLog.d(
          "CALLS_FGS",
          "onStartCommand action=START sdk=${Build.VERSION.SDK_INT} startId=$startId needsMic=$needsMicrophone incomingCall=$isIncomingCall call_id=${incomingCallId ?: "<none>"}"
        )
        isStarting = true
        pendingStop = false
        val started = if (isIncomingCall && incomingCallId != null && incomingFrom != null) {
          startForegroundForIncomingCall(incomingCallId, incomingFrom, displayName, callUuid, needsMicrophone)
        } else {
          startForegroundCompat(NOTIF_ID, getNotification(), needsMicrophone, isCallStyle = false)
        }
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
        cancelCurrentNotification()
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
    cancelCurrentNotification()
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

  private fun startForegroundCompat(
    notificationId: Int,
    notification: Notification,
    needsMicrophone: Boolean,
    isCallStyle: Boolean
  ): Boolean {
    val started = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
      val types = buildForegroundServiceTypes(needsMicrophone)
      CallLog.d(
        "CALLS_FGS",
        "startForeground id=$notificationId callStyle=$isCallStyle types=0x${types.toString(16)} needsMic=$needsMicrophone"
      )
      startForegroundWithTypes(notificationId, types, notification, isCallStyle)
    } else {
      CallLog.d(
        "CALLS_FGS",
        "startForeground id=$notificationId callStyle=$isCallStyle needsMic=$needsMicrophone"
      )
      startForegroundSafe(notificationId, notification, isCallStyle)
    }
    if (started) {
      currentNotifId = notificationId
    }
    hasStartedForeground = started
    return started
  }

  private fun startForegroundForIncomingCall(
    callId: String,
    from: String,
    displayName: String?,
    callUuid: String?,
    needsMicrophone: Boolean
  ): Boolean {
    val incomingNotification = NotificationHelper.buildIncomingNotification(
      this,
      callId,
      from,
      displayName,
      callUuid,
      isRinging = true,
      attachFullScreen = true,
      useCallStyle = true
    )
    val notificationId = incomingNotification.meta.baseId
    val started = startForegroundCompat(
      notificationId,
      incomingNotification.notification,
      needsMicrophone,
      isCallStyle = incomingNotification.meta.usedCallStyle
    )
    if (started) {
      CallLog.d(
        "CALLS_NOTIF",
        "callstyle-post accepted foreground=true call_id=$callId call_uuid=${incomingNotification.meta.effectiveCallUuid}"
      )
      return true
    }
    CallLog.e(
      "CALLS_NOTIF",
      "callstyle-post rejected foreground=false call_id=$callId call_uuid=${incomingNotification.meta.effectiveCallUuid}"
    )
    val fallbackNotification = NotificationHelper.buildIncomingNotification(
      this,
      callId,
      from,
      displayName,
      callUuid,
      isRinging = true,
      attachFullScreen = true,
      useCallStyle = false,
      forceFullScreenIntent = true
    )
    val fallbackStarted = startForegroundCompat(
      notificationId,
      fallbackNotification.notification,
      needsMicrophone,
      isCallStyle = false
    )
    if (fallbackStarted) {
      CallLog.d(
        "CALLS_NOTIF",
        "fallback notification posted call_id=$callId call_uuid=${fallbackNotification.meta.effectiveCallUuid}"
      )
    } else {
      CallLog.e(
        "CALLS_NOTIF",
        "fallback startForeground failed call_id=$callId call_uuid=${fallbackNotification.meta.effectiveCallUuid}"
      )
    }
    return fallbackStarted
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

  private fun cancelCurrentNotification() {
    val manager = getSystemService(NotificationManager::class.java) ?: return
    try {
      manager.cancel(currentNotifId)
    } catch (error: Throwable) {
      CallLog.e(
        "CALLS_FGS",
        "cancel notification id=$currentNotifId failed: $error",
        error
      )
    }
  }

  private fun startForegroundSafe(notificationId: Int, notification: Notification, isCallStyle: Boolean): Boolean {
    return try {
      startForeground(notificationId, notification)
      true
    } catch (error: Throwable) {
      CallLog.e(
        "CALLS_FGS",
        "startForeground(safe) failed callStyle=$isCallStyle: $error",
        error
      )
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

  private fun startForegroundWithTypes(notificationId: Int, types: Int, notification: Notification, isCallStyle: Boolean): Boolean {
    return try {
      startForeground(notificationId, notification, types)
      true
    } catch (error: Throwable) {
      CallLog.e(
        "CALLS_FGS",
        "startForeground types failure callStyle=$isCallStyle ${error::class.java.simpleName}: ${error.message}",
        error
      )
      val fallback = types and ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE.inv()
      if (fallback != types) {
        try {
          startForeground(notificationId, notification, fallback)
          return true
        } catch (fallbackEx: Throwable) {
          CallLog.e(
            "CALLS_FGS",
            "fallback startForeground(types=$fallback) failed callStyle=$isCallStyle: $fallbackEx",
            fallbackEx
          )
        }
      }
      return startForegroundSafe(notificationId, notification, isCallStyle)
    }
  }

  private fun hasMicrophonePermission(): Boolean {
    return ContextCompat.checkSelfPermission(
      this,
      Manifest.permission.RECORD_AUDIO,
    ) == PackageManager.PERMISSION_GRANTED
  }

}
