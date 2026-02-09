package com.sip_mvp.app

import android.app.NotificationManager
import android.content.Context
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage


class IncomingFcmService : FirebaseMessagingService() {
  private val notificationManager: NotificationManager
    get() = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

  override fun onMessageReceived(message: RemoteMessage) {
    super.onMessageReceived(message)
    val type = message.data["type"] ?: return
    when (type) {
      "incoming_call" -> showIncoming(message)
      "call_cancelled" -> cancelCall(message)
    }
  }

  private fun showIncoming(message: RemoteMessage) {
    if (EngineStateStore.isEngineAlive(applicationContext)) {
      return
    }
    if (isExpired(message)) {
      return
    }
    val callId = message.data["call_id"] ?: return
    val from = message.data["from"] ?: return
    val displayName = message.data["display_name"]
    NotificationHelper.showIncoming(
      applicationContext,
      notificationManager,
      callId,
      from,
      displayName
    )
  }

  private fun cancelCall(message: RemoteMessage) {
    val callId = message.data["call_id"] ?: return
    NotificationHelper.cancel(notificationManager, callId)
  }
}
  private fun isExpired(message: RemoteMessage): Boolean {
    val ts = message.data["ts"]?.toLongOrNull()
    val ttl = message.data["ttl_s"]?.toLongOrNull()
    if (ts == null || ttl == null) {
      return false
    }
    val now = System.currentTimeMillis() / 1000
    return now > ts + ttl + 5
  }
