package com.sip_mvp.app

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import androidx.core.app.ActivityCompat

class IncomingCallActivity : Activity() {
  override fun onCreate(savedInstanceState: Bundle?) {
    ActivityCompat.setShowWhenLocked(this, true)
    ActivityCompat.setTurnScreenOn(this, true)
    super.onCreate(savedInstanceState)
    val mainIntent = Intent(this, MainActivity::class.java).apply {
      action = intent.action
      putExtras(intent)
      addFlags(
        Intent.FLAG_ACTIVITY_NEW_TASK or
            Intent.FLAG_ACTIVITY_CLEAR_TOP or
            Intent.FLAG_ACTIVITY_SINGLE_TOP
      )
    }
    startActivity(mainIntent)
    finish()
  }
}
