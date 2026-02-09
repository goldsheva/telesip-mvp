package com.sip_mvp.app

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.os.Build
import android.util.Log

object AudioFocusHelper {
  private const val TAG = "AudioFocusHelper"
  private val focusListener = AudioManager.OnAudioFocusChangeListener { }
  private var focusRequest: AudioFocusRequest? = null

  fun acquire(context: Context, callId: String) {
    val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    release(context)
    val attributes = AudioAttributes.Builder()
      .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
      .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
      .build()
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
      focusRequest = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT)
        .setAudioAttributes(attributes)
        .setOnAudioFocusChangeListener(focusListener)
        .build()
      val result = audioManager.requestAudioFocus(focusRequest!!)
      Log.d(TAG, "acquireAudioFocus callId=$callId result=$result")
    } else {
      val result = audioManager.requestAudioFocus(
        focusListener,
        AudioManager.STREAM_VOICE_CALL,
        AudioManager.AUDIOFOCUS_GAIN_TRANSIENT
      )
      Log.d(TAG, "acquireAudioFocus (legacy) callId=$callId result=$result")
    }
  }

  fun release(context: Context) {
    val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
      focusRequest?.let {
        audioManager.abandonAudioFocusRequest(it)
        focusRequest = null
      }
    } else {
      audioManager.abandonAudioFocus(focusListener)
    }
    Log.d(TAG, "releaseAudioFocus")
  }
}
