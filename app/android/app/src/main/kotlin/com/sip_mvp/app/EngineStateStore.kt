package com.sip_mvp.app

import android.content.Context

object EngineStateStore {
  private const val PREF_NAME = "app_lifecycle"
  private const val KEY_ENGINE_ALIVE = "engine_alive"

  fun setEngineAlive(context: Context, alive: Boolean) {
    val prefs = context.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
    prefs.edit().putBoolean(KEY_ENGINE_ALIVE, alive).apply()
  }

  fun isEngineAlive(context: Context): Boolean {
    val prefs = context.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
    return prefs.getBoolean(KEY_ENGINE_ALIVE, false)
  }
}
