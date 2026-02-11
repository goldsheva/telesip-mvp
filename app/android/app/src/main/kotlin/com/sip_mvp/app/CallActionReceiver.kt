package com.sip_mvp.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
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
    val prefs = context.getSharedPreferences("pending_call_actions", Context.MODE_PRIVATE)
    val raw = prefs.getString("pending_call_actions", "[]")
    val existing = mutableListOf<JSONObject>()
    JSONArray(raw ?: "[]").let { array ->
      for (i in 0 until array.length()) {
        array.optJSONObject(i)?.let { existing.add(it) }
      }
    }
    val now = System.currentTimeMillis()
    val entry = JSONObject().apply {
      put("type", action)
      put("callId", callId)
      put("ts", now)
      put("call_id", callId)
      put("action", action)
      put("timestamp", now)
    }
    existing.add(entry)
    while (existing.size > 10) {
      existing.removeAt(0)
    }
    val updated = JSONArray()
    existing.forEach { updated.put(it) }
    prefs.edit().putString("pending_call_actions", updated.toString()).apply()
    CallActionStore.save(context, callId, action, System.currentTimeMillis())
    NotificationHelper.cancel(context.getSystemService(Context.NOTIFICATION_SERVICE) as android.app.NotificationManager, callId)
    val main = Intent(context, MainActivity::class.java).apply {
      putExtra("call_id", callId)
      putExtra("action", action)
      addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
    }
    context.startActivity(main)
  }
}
