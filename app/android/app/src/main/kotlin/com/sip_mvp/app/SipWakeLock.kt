package com.sip_mvp.app

import android.content.Context
import android.os.PowerManager
import android.util.Log

object SipWakeLock {
  private const val TAG = "SipWakeLock"
  private const val LOCK_TAG = "SipWakeLock:Coarse"
  private const val TIMEOUT_MS = 10 * 60 * 1000L
  private var wakeLock: PowerManager.WakeLock? = null

  fun acquire(context: Context) {
    val manager = context.getSystemService(Context.POWER_SERVICE) as? PowerManager ?: return
    if (wakeLock?.isHeld == true) {
      Log.d(TAG, "wakeLock already held")
      return
    }
    wakeLock = manager.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, LOCK_TAG)
    wakeLock?.acquire(TIMEOUT_MS)
    Log.d(TAG, "wakeLock acquired")
  }

  fun release() {
    val current = wakeLock ?: return
    if (!current.isHeld) {
      wakeLock = null
      return
    }
    current.release()
    Log.d(TAG, "wakeLock released")
    wakeLock = null
  }

  fun isHeld(): Boolean {
    return wakeLock?.isHeld == true
  }
}
