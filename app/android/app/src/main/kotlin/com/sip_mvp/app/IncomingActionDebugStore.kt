package com.sip_mvp.app

import android.content.Context

object IncomingActionDebugStore {
  private const val PREF_NAME = "incoming_action_debug"
  private const val KEY_TS = "last_incoming_action_ts"
  private const val KEY_TYPE = "last_incoming_action_type"
  private const val KEY_CALL_ID = "last_incoming_action_call_id"
  private const val KEY_SOURCE = "last_incoming_action_source"

  data class LastIncomingAction(
    val timestamp: Long,
    val actionType: String?,
    val callId: String?,
    val source: String?,
  ) {
    fun toMap(): Map<String, Any?> = mapOf(
      "timestamp" to timestamp,
      "type" to actionType,
      "callId" to callId,
      "source" to source,
    )
  }

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

  fun read(context: Context): LastIncomingAction? {
    val prefs = context.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
    if (!prefs.contains(KEY_TS)) return null
    val timestamp = prefs.getLong(KEY_TS, -1L)
    if (timestamp <= 0L) return null
    val actionType = prefs.getString(KEY_TYPE, null)
    val callId = prefs.getString(KEY_CALL_ID, null)
    val source = prefs.getString(KEY_SOURCE, null)
    return LastIncomingAction(
      timestamp = timestamp,
      actionType = actionType,
      callId = callId,
      source = source,
    )
  }
}
