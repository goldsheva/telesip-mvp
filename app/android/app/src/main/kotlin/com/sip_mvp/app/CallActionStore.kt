package com.sip_mvp.app

import android.content.Context

object CallActionStore {
  private const val PREF_NAME = "call_action"
  private const val KEY_CALL_ID = "call_id"
  private const val KEY_ACTION = "action"
  private const val KEY_TS = "timestamp"

  fun save(context: Context, callId: String, action: String, timestamp: Long) {
    val prefs = context.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
    prefs.edit()
        .putString(KEY_CALL_ID, callId)
        .putString(KEY_ACTION, action)
        .putLong(KEY_TS, timestamp)
        .apply()
  }

  fun read(context: Context): CallAction? {
    val prefs = context.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
    val callId = prefs.getString(KEY_CALL_ID, null) ?: return null
    val action = prefs.getString(KEY_ACTION, null) ?: return null
    val ts = prefs.getLong(KEY_TS, 0L)
    return CallAction(callId, action, ts)
  }

  fun clear(context: Context) {
    context.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
        .edit()
        .clear()
        .apply()
  }
}

data class CallAction(val callId: String, val action: String, val timestamp: Long)
