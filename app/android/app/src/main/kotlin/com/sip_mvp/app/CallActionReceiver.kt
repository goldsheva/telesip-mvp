package com.sip_mvp.app

import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject

class CallActionReceiver : BroadcastReceiver() {
  companion object {
    const val ACTION_ANSWER = "com.sip_mvp.app.ACTION_ANSWER"
    const val ACTION_DECLINE = "com.sip_mvp.app.ACTION_DECLINE"
  }

  override fun onReceive(context: Context, intent: Intent) {
    val callId = intent.getStringExtra("call_id") ?: return
    val action = when (intent.action) {
      ACTION_ANSWER -> "answer"
      ACTION_DECLINE -> "decline"
      else -> return
    }
    val notificationManager =
      context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
    val isCallIdValid = callId.isNotBlank() && callId != "<none>"
    var cancelAttempted = false
    var cancelSucceeded = false
    if (isCallIdValid && notificationManager != null) {
      cancelAttempted = true
      try {
        NotificationHelper.cancel(notificationManager, callId)
        cancelSucceeded = true
      } catch (error: Throwable) {
        Log.d("CallActionReceiver", "notification cancel failed action=$action call=$callId: $error")
      }
    }
    Log.d(
      "CallActionReceiver",
      "action=$action call=$callId cancelAttempted=$cancelAttempted cancelSucceeded=$cancelSucceeded",
    )
    val prefs = context.getSharedPreferences("pending_call_actions", Context.MODE_PRIVATE)
    val raw = prefs.getString("pending_call_actions", "[]")
    val existing = mutableListOf<JSONObject>()
    JSONArray(raw ?: "[]").let { array ->
      for (i in 0 until array.length()) {
        array.optJSONObject(i)?.let { existing.add(it) }
      }
    }
    val now = System.currentTimeMillis()
    var duplicateSuppressed = false
    val entry = JSONObject().apply {
      put("type", action)
      put("callId", callId)
      put("ts", now)
      put("call_id", callId)
      put("action", action)
      put("timestamp", now)
    }
    val dedupWindow = 2000L
    for (existingEntry in existing) {
      val existingAction = existingEntry.optString("type").ifEmpty { existingEntry.optString("action") }
      val existingCallId = existingEntry.optString("callId").ifEmpty { existingEntry.optString("call_id") }
      if (existingAction == action && existingCallId == callId) {
        val previousTs = existingEntry.optLong("ts", 0L)
        if (now - previousTs <= dedupWindow) {
          duplicateSuppressed = true
          Log.d(
            "CallActionReceiver",
            "duplicate pending action suppressed action=$action call=$callId ts=$previousTs",
          )
          break
        }
      }
    }
    if (!duplicateSuppressed) {
      existing.add(entry)
      while (existing.size > 10) {
        existing.removeAt(0)
      }
      val updated = JSONArray()
      existing.forEach { updated.put(it) }
      prefs.edit().putString("pending_call_actions", updated.toString()).apply()
    }
    CallActionStore.save(context, callId, action, System.currentTimeMillis())
    val main = Intent(context, MainActivity::class.java).apply {
      putExtra("call_id", callId)
      putExtra("action", action)
      addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
    }
    context.startActivity(main)
  }
}
