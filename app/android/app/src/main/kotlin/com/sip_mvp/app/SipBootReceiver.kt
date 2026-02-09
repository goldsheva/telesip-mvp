package com.sip_mvp.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

class SipBootReceiver : BroadcastReceiver() {
  override fun onReceive(context: Context, intent: Intent) {
    if (intent.action == Intent.ACTION_BOOT_COMPLETED) {
      Log.d("SipBootReceiver", "BOOT_COMPLETED received")
      context.getSharedPreferences("app_prefs", Context.MODE_PRIVATE)
        .edit()
        .putBoolean("sip_boot_completed", true)
        .apply()
    }
  }
}
