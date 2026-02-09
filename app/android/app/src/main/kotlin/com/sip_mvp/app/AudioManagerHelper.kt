package com.sip_mvp.app

import android.content.Context
import android.media.AudioManager

object AudioManagerHelper {
  private var scoStarted = false

  fun startBluetoothSco(context: Context) {
    val manager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    if (scoStarted) return
    manager.mode = AudioManager.MODE_IN_COMMUNICATION
    manager.startBluetoothSco()
    scoStarted = true
  }

  fun stopBluetoothSco(context: Context) {
    val manager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    if (!scoStarted) return
    manager.stopBluetoothSco()
    scoStarted = false
    manager.mode = AudioManager.MODE_NORMAL
  }
}
