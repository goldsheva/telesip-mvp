package com.sip_mvp.app

import android.app.ActivityManager
import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Process
import com.sip_mvp.app.CallLog
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
    val callUuid = intent.getStringExtra("call_uuid")
    val importance = try {
      (context.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager)
        ?.runningAppProcesses
        ?.firstOrNull { it.pid == Process.myPid() }
        ?.importance
    } catch (_: Exception) {
      null
    }
    CallLog.d(
      "CALLS_ACTION",
      "resolved action=$action call_id=$callId call_uuid=${callUuid ?: "<none>"} importance=$importance"
    )
    val validCallId = callId.takeIf { it.isNotBlank() && it != "<none>" }
    val validCallUuid = callUuid?.takeIf { it.isNotBlank() && it != "<none>" }
    val idsToCancel = buildSet<String> {
      validCallId?.let { add(it) }
      validCallUuid?.let { add(it) }
    }
    var cancelAttempted = 0
    var cancelSucceeded = 0
    if (idsToCancel.isNotEmpty()) {
      if (notificationManager != null) {
        cancelAttempted = idsToCancel.size
        for (id in idsToCancel) {
          try {
            NotificationHelper.cancel(notificationManager, id)
            cancelSucceeded += 1
          } catch (error: Throwable) {
            CallLog.w("CALLS_ACTION", "notification cancel failed action=$action call=$id: $error")
          }
        }
      }
      NotificationHelper.markSuppressed(idsToCancel)
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
        var previousTs = existingEntry.optLong("ts", 0L)
        if (previousTs == 0L) {
          previousTs = existingEntry.optLong("timestamp", 0L)
        }
        if (previousTs > 0 && now - previousTs <= dedupWindow) {
          duplicateSuppressed = true
          CallLog.d(
            "CALLS_ACTION",
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
    CallLog.d(
      "CALLS_ACTION",
      "action=$action ids=$idsToCancel hasManager=${notificationManager != null} cancelAttempted=$cancelAttempted cancelSucceeded=$cancelSucceeded duplicateSuppressed=$duplicateSuppressed",
    )
    val primaryId = validCallId ?: validCallUuid ?: "<none>"
    CallActionStore.save(context, primaryId, action, System.currentTimeMillis())
    CallLog.d(
      "CALLS_ACTION",
      "action_enqueued action=$action call_id=$callId call_uuid=$callUuid duplicateSuppressed=$duplicateSuppressed",
    )
    val main = Intent(context, MainActivity::class.java).apply {
      putExtra("call_id", callId)
      putExtra("action", action)
      addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
    }
    context.startActivity(main)
  }
}
