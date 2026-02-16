package com.sip_mvp.app

import android.app.Activity
import android.app.KeyguardManager
import android.content.Intent
import android.media.AudioAttributes
import android.media.Ringtone
import android.media.RingtoneManager
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import android.widget.Button
import android.widget.TextView

class IncomingCallActivity : Activity() {
  private var nativeRingtone: Ringtone? = null

  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    CallLog.ensureInit(applicationContext)
    CallLog.d(
      "IncomingCallActivity",
      "onCreate action=${intent?.action} extras=${intent?.extras?.keySet()?.joinToString(",") ?: "<none>"} api=${Build.VERSION.SDK_INT}",
    )
    applyLockScreenFlags()
    val keyguardManager = getSystemService(KeyguardManager::class.java)
    val locked = keyguardManager?.isKeyguardLocked ?: false
    CallLog.d("IncomingCallActivity", "keyguard locked=$locked")
    if (locked) {
      CallLog.d("IncomingCallActivity", "acting as lockscreen UI host (native)")
      showNativeIncomingUi()
      return
    }
    CallLog.d("IncomingCallActivity", "acting as trampoline -> forwarding to MainActivity locked=$locked")
    CallLog.d("IncomingCallActivity", "Forwarding to MainActivity with wake flags applied")
    startActivity(buildMainIntent())
    finish()
  }

  private fun showNativeIncomingUi() {
    setContentView(R.layout.activity_incoming_call)
    val from = intent.getStringExtra("from")
    val displayName = intent.getStringExtra("display_name")
    val title = displayName?.takeIf { it.isNotBlank() } ?: from ?: "Incoming call"
    findViewById<TextView>(R.id.incomingCaller).text = title
    findViewById<Button>(R.id.incomingDecline).setOnClickListener {
      CallLog.d("IncomingCallActivity", "native decline pressed")
      stopNativeRingtone()
      sendCallAction(CallActionReceiver.ACTION_DECLINE)
      finish()
    }
    findViewById<Button>(R.id.incomingAnswer).setOnClickListener {
      CallLog.d("IncomingCallActivity", "native answer pressed")
      stopNativeRingtone()
      sendCallAction(CallActionReceiver.ACTION_ANSWER)
      startActivity(buildMainIntent())
      finish()
    }
    startNativeRingtone()
  }

  private fun sendCallAction(action: String) {
    val callId = intent.getStringExtra("call_id")
    val callUuid = intent.getStringExtra("call_uuid")
    val actionIntent = Intent(this, CallActionReceiver::class.java).apply {
      this.action = action
      putExtra("call_id", callId)
      putExtra("call_uuid", callUuid)
    }
    sendBroadcast(actionIntent)
  }

  private fun buildMainIntent(): Intent {
    return Intent(this, MainActivity::class.java).apply {
      action = intent.action
      putExtras(intent)
      putExtra(MainActivity.EXTRA_CHECK_PENDING_HINT, true)
      addFlags(
        Intent.FLAG_ACTIVITY_NEW_TASK or
            Intent.FLAG_ACTIVITY_CLEAR_TOP or
            Intent.FLAG_ACTIVITY_SINGLE_TOP
      )
    }
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

  override fun onDestroy() {
    stopNativeRingtone()
    super.onDestroy()
  }

  private fun startNativeRingtone() {
    if (nativeRingtone?.isPlaying == true) return
    try {
      val ringtoneUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
      val ringtone = RingtoneManager.getRingtone(this, ringtoneUri) ?: return
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
        ringtone.audioAttributes =
          AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()
      } else {
        @Suppress("DEPRECATION")
        ringtone.streamType = android.media.AudioManager.STREAM_RING
      }
      ringtone.play()
      nativeRingtone = ringtone
      CallLog.d("IncomingCallActivity", "native ringtone started")
    } catch (error: Exception) {
      CallLog.w("IncomingCallActivity", "native ringtone start failed: $error")
    }
  }

  private fun stopNativeRingtone() {
    try {
      nativeRingtone?.stop()
      CallLog.d("IncomingCallActivity", "native ringtone stopped")
    } catch (error: Exception) {
      CallLog.w("IncomingCallActivity", "native ringtone stop failed: $error")
    } finally {
      nativeRingtone = null
    }
  }
}
