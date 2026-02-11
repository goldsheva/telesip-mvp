package com.sip_mvp.app

import android.Manifest
import android.app.KeyguardManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.SystemClock
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import androidx.core.app.Person
import com.sip_mvp.app.BuildConfig

object NotificationHelper {
  private const val CHANNEL_ID = "calls"
  private const val CHANNEL_NAME = "Calls"
  private const val SUPPRESSION_TTL_MS = 2_000L
  private val suppressionExpiry = mutableMapOf<String, Long>()

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
    displayName: String?,
    callUuid: String? = null,
    isRinging: Boolean
  ) {
    ensureChannel(context, notificationManager)
    if (isSuppressed(callId, callUuid)) {
      if (BuildConfig.DEBUG) {
        Log.d("NotificationHelper", "incoming suppressed call_id=$callId call_uuid=$callUuid")
      }
      return
    }
    val meta = prepareIncomingNotification(
      context,
      callId,
      from,
      displayName,
      callUuid,
      attachFullScreen = true,
    )
    val notification = buildNotification(meta, isRinging)
    if (BuildConfig.DEBUG) {
      Log.d(
        "NotificationHelper",
        "notify baseId=${meta.baseId} call_id=$callId call_uuid=${meta.effectiveCallUuid} isRinging=$isRinging keyguardLocked=${meta.keyguardLocked} api=${Build.VERSION.SDK_INT} callStyle=${meta.usedCallStyle}",
      )
    }
    notificationManager.notify(meta.baseId, notification)
  }

  fun updateIncomingState(
    context: Context,
    notificationManager: NotificationManager,
    callId: String,
    from: String,
    displayName: String?,
    callUuid: String? = null,
    isRinging: Boolean
  ) {
    ensureChannel(context, notificationManager)
    val meta = prepareIncomingNotification(
      context,
      callId,
      from,
      displayName,
      callUuid,
      attachFullScreen = false,
    )
    val notification = buildNotification(meta, isRinging)
    if (BuildConfig.DEBUG) {
      Log.d(
        "NotificationHelper",
        "update baseId=${meta.baseId} call_id=$callId call_uuid=${meta.effectiveCallUuid} isRinging=$isRinging api=${Build.VERSION.SDK_INT}",
      )
    }
    notificationManager.notify(meta.baseId, notification)
  }

  private fun buildNotification(
    meta: IncomingNotificationMeta,
    isRinging: Boolean
  ): Notification {
    val notification = meta.builder.build()
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S && isRinging) {
      notification.flags = notification.flags or Notification.FLAG_INSISTENT
    }
    return notification
  }

  private fun prepareIncomingNotification(
    context: Context,
    callId: String,
    from: String,
    displayName: String?,
    callUuid: String?,
    attachFullScreen: Boolean,
  ): IncomingNotificationMeta {
    val effectiveCallUuid = callUuid ?: callId
    val baseId = getNotificationId(callId)
    val keyguardLocked = shouldUseFullScreenIntent(context)
    val incomingIntent = Intent(context, IncomingCallActivity::class.java).apply {
      putExtra("call_id", callId)
      putExtra("call_uuid", effectiveCallUuid)
      putExtra("from", from)
      putExtra("display_name", displayName)
      action = "open_incoming"
      addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
    }
    val fullScreenIntent = PendingIntent.getActivity(
      context,
      reqCode(baseId, 0),
      incomingIntent,
      PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
    )
    val main = mainIntent(context, callId, from, displayName)
    main.putExtra("call_uuid", effectiveCallUuid)
    val contentIntent = PendingIntent.getActivity(
      context,
      reqCode(baseId, 1),
      main,
      PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
    )
    val answerIntent = PendingIntent.getBroadcast(
      context,
      reqCode(baseId, 2),
      Intent(CallActionReceiver.ACTION_ANSWER).apply {
        putExtra("call_id", callId)
        putExtra("call_uuid", effectiveCallUuid)
      },
      PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_ONE_SHOT
    )
    val declineIntent = PendingIntent.getBroadcast(
      context,
      reqCode(baseId, 3),
      Intent(CallActionReceiver.ACTION_DECLINE).apply {
        putExtra("call_id", callId)
        putExtra("call_uuid", effectiveCallUuid)
      },
      PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_ONE_SHOT
    )
    val callerPerson = Person.Builder()
      .setName(displayName ?: from)
      .setImportant(true)
      .build()
    val builder = NotificationCompat.Builder(context, CHANNEL_ID)
      .setContentTitle(displayName ?: "Incoming call")
      .setContentText("From $from")
      .setSmallIcon(R.mipmap.ic_launcher)
      .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
      .setPriority(NotificationCompat.PRIORITY_HIGH)
      .setCategory(NotificationCompat.CATEGORY_CALL)
      .setDefaults(NotificationCompat.DEFAULT_ALL)
      .setOngoing(true)
      .setAutoCancel(false)
      .setOnlyAlertOnce(true)
      .setWhen(System.currentTimeMillis())
      .setShowWhen(false)
      .apply {
        if (attachFullScreen && keyguardLocked) {
          setFullScreenIntent(fullScreenIntent, true)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
          setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
        }
      }
      .setContentIntent(contentIntent)
    val usedCallStyle = Build.VERSION.SDK_INT >= Build.VERSION_CODES.S
    if (!usedCallStyle) {
      builder
        .addAction(android.R.drawable.ic_menu_call, "Answer", answerIntent)
        .addAction(android.R.drawable.ic_menu_close_clear_cancel, "Decline", declineIntent)
    } else {
      builder.setStyle(
        NotificationCompat.CallStyle.forIncomingCall(
          callerPerson,
          declineIntent,
          answerIntent
        )
      )
    }
    return IncomingNotificationMeta(
      builder = builder,
      baseId = baseId,
      effectiveCallUuid = effectiveCallUuid,
      keyguardLocked = keyguardLocked,
      usedCallStyle = usedCallStyle
    )
  }

  private data class IncomingNotificationMeta(
    val builder: NotificationCompat.Builder,
    val baseId: Int,
    val effectiveCallUuid: String,
    val keyguardLocked: Boolean,
    val usedCallStyle: Boolean
  )

  private fun mainIntent(context: Context, callId: String, from: String, displayName: String?): Intent {
    return Intent(context, MainActivity::class.java).apply {
      putExtra("call_id", callId)
      putExtra("action", "open_incoming")
      putExtra("from", from)
      putExtra("display_name", displayName)
      addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
    }
  }

  fun getNotificationDebugState(
    context: Context,
    notificationManager: NotificationManager,
  ): Map<String, Any?> {
    val compat = NotificationManagerCompat.from(context)
    val channel = notificationManager.getNotificationChannel(CHANNEL_ID)
    val keyguardManager =
      context.getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager
    val keyguardState = keyguardManager?.isKeyguardLocked
    val hasPermission = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
      ContextCompat.checkSelfPermission(
        context,
        android.Manifest.permission.POST_NOTIFICATIONS,
      ) == android.content.pm.PackageManager.PERMISSION_GRANTED
    } else {
      true
    }
    return mapOf(
      "notificationsEnabled" to compat.areNotificationsEnabled(),
      "channelImportance" to channel?.importance,
      "channelEnabled" to (channel != null && channel.importance != NotificationManager.IMPORTANCE_NONE),
      "channelExists" to (channel != null),
      "hasPostNotificationsPermission" to hasPermission,
      "keyguardLocked" to keyguardState,
    )
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

  fun markSuppressed(keys: Collection<String>) {
    val now = SystemClock.uptimeMillis()
    val expiry = now + SUPPRESSION_TTL_MS
    val addedKeys = mutableListOf<String>()
    synchronized(suppressionExpiry) {
      cleanupSuppression()
      for (key in keys) {
        if (key.isBlank() || key == "<none>") continue
        if (addSuppression(key, expiry)) {
          addedKeys.add(key)
        }
      }
    }
    if (BuildConfig.DEBUG && addedKeys.isNotEmpty()) {
      Log.d(
        "NotificationHelper",
        "markSuppressed keys=$addedKeys deltaMs=${expiry - now}",
      )
    }
  }

  private fun isSuppressed(callId: String, callUuid: String?): Boolean {
    val now = SystemClock.uptimeMillis()
    synchronized(suppressionExpiry) {
      cleanupSuppression()
      if (suppressionExpiry.containsKey(callId)) return true
      if (!callUuid.isNullOrBlank() && suppressionExpiry.containsKey(callUuid)) return true
    }
    return false
  }

  private fun cleanupSuppression() {
    val now = SystemClock.uptimeMillis()
    val iterator = suppressionExpiry.entries.iterator()
    while (iterator.hasNext()) {
      if (iterator.next().value <= now) {
        iterator.remove()
      }
    }
  }

  private fun addSuppression(key: String, expiry: Long): Boolean {
    if (key.isBlank()) return false
    suppressionExpiry[key] = expiry
    return true
  }

  private fun reqCode(baseId: Int, offset: Int): Int {
    return (baseId + offset) and 0x7fffffff
  }
}
