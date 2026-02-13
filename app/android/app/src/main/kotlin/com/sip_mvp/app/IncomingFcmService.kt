package com.sip_mvp.app

import android.util.Log
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone


class IncomingFcmService : FirebaseMessagingService() {

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
    if (message.data["call_id"] == null) return
    persistPendingHint(message)
  }

  private fun cancelCall(message: RemoteMessage) {
    CallActionStore.clear(applicationContext)
    PendingIncomingHintWriter.clear(applicationContext)
    IncomingCallNotificationHelper.cancelIncomingNotification(applicationContext)
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

  private fun persistPendingHint(message: RemoteMessage) {
    try {
      val payload = JSONObject()
      message.data.forEach { (key, value) ->
        payload.put(key, value)
      }
      val record = JSONObject()
        .put("timestamp", isoTimestamp())
        .put("payload", payload)
        .toString()
      PendingIncomingHintWriter.persist(applicationContext, record)
      val posted =
        IncomingCallNotificationHelper.showIncomingNotificationFromPendingHint(
          applicationContext,
        )
      Log.d(
        "IncomingHint",
        "pending hint persisted notificationPosted=$posted callId=${payload.optString("call_id", "<none>")}",
      )
    } catch (error: Exception) {
      Log.w("IncomingHint", "failed to persist pending hint: $error")
    }
  }

  private fun isoTimestamp(): String {
    val formatter = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US)
    formatter.timeZone = TimeZone.getTimeZone("UTC")
    return formatter.format(Date())
  }
}
