package com.sip_mvp.app

import android.content.Context

object IncomingActionDebugStore {
  private const val PREF_NAME = "incoming_action_debug"
  private const val KEY_TS = "last_incoming_action_ts"
  private const val KEY_TYPE = "last_incoming_action_type"
  private const val KEY_CALL_ID = "last_incoming_action_call_id"
  private const val KEY_SOURCE = "last_incoming_action_source"

  fun persist(
    context: Context,
    timestamp: Long,
    actionType: String,
    callId: String,
    source: String,
  ) {
    val prefs = context.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
    prefs.edit()
      .putLong(KEY_TS, timestamp)
      .putString(KEY_TYPE, actionType)
      .putString(KEY_CALL_ID, callId)
      .putString(KEY_SOURCE, source)
      .apply()
  }
}
