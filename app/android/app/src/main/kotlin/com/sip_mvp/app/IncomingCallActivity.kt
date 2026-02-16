package com.sip_mvp.app

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.os.Build
import android.view.WindowManager

class IncomingCallActivity : Activity() {
  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    CallLog.ensureInit(applicationContext)
    CallLog.d(
      "IncomingCallActivity",
      "onCreate action=${intent?.action} extras=${intent?.extras?.keySet()?.joinToString(",") ?: "<none>"} api=${Build.VERSION.SDK_INT}",
    )
    applyLockScreenFlags()
    val mainIntent = Intent(this, MainActivity::class.java).apply {
      action = intent.action
      putExtras(intent)
      addFlags(
        Intent.FLAG_ACTIVITY_NEW_TASK or
            Intent.FLAG_ACTIVITY_CLEAR_TOP or
            Intent.FLAG_ACTIVITY_SINGLE_TOP
      )
    }
    CallLog.d("IncomingCallActivity", "Forwarding to MainActivity with wake flags applied")
    startActivity(mainIntent)
    finish()
  }

  private fun applyLockScreenFlags() {
    val legacyFlags =
      WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
        WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
        WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON

    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
      setShowWhenLocked(true)
      setTurnScreenOn(true)
      window.addFlags(legacyFlags)
    } else {
      window.addFlags(legacyFlags)
    }
    CallLog.d("IncomingCallActivity", "applyLockScreenFlags done")
  }

  override fun onResume() {
    super.onResume()
    window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
  }

  override fun onPause() {
    window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    super.onPause()
  }
}
