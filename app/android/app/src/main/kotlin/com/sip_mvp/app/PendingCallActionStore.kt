package com.sip_mvp.app

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

object PendingCallActionStore {
  private const val PREF_NAME = "pending_call_actions"
  private const val KEY_PENDING_ACTIONS = "pending_call_actions"
  private const val MAX_ENTRIES = 10
  private const val DEDUP_WINDOW_MS = 2000L

  fun enqueue(context: Context, callId: String, actionType: String, timestamp: Long): Boolean {
    val prefs = context.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
    val raw = prefs.getString(KEY_PENDING_ACTIONS, "[]")
    val existing = mutableListOf<JSONObject>()
    JSONArray(raw ?: "[]").let { array ->
      for (i in 0 until array.length()) {
        array.optJSONObject(i)?.let { existing.add(it) }
      }
    }

    val entry = JSONObject().apply {
      put("type", actionType)
      put("callId", callId)
      put("ts", timestamp)
      put("call_id", callId)
      put("action", actionType)
      put("timestamp", timestamp)
    }

    var dedupSuppressed = false
    for (existingEntry in existing) {
      val existingAction =
        existingEntry.optString("type").ifEmpty { existingEntry.optString("action") }
      val existingCallId =
        existingEntry.optString("callId").ifEmpty { existingEntry.optString("call_id") }
      if (existingAction == actionType && existingCallId == callId) {
        var previousTs = existingEntry.optLong("ts", 0L)
        if (previousTs == 0L) {
          previousTs = existingEntry.optLong("timestamp", 0L)
        }
        if (previousTs > 0 && timestamp - previousTs <= DEDUP_WINDOW_MS) {
          dedupSuppressed = true
          break
        }
      }
    }
    if (dedupSuppressed) {
      CallLog.d(
        "IncomingHint",
        "pending action deduped type=$actionType callId=$callId",
      )
      return false
    }

    existing.add(entry)
    while (existing.size > MAX_ENTRIES) {
      existing.removeAt(0)
    }

    val updated = JSONArray()
    existing.forEach { updated.put(it) }
    prefs.edit().putString(KEY_PENDING_ACTIONS, updated.toString()).apply()
    CallLog.d(
      "IncomingHint",
      "pending action enqueued type=$actionType callId=$callId ts=$timestamp",
    )
    return true
  }
}
