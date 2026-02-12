package com.sip_mvp.app

import android.bluetooth.BluetoothAdapter
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.AudioManager
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import androidx.core.content.ContextCompat

class CallsAudioRouteBridge(
  private val context: Context,
  messenger: BinaryMessenger
) {

  companion object {
    fun register(messenger: BinaryMessenger, context: Context) {
      CallsAudioRouteBridge(context, messenger)
    }
  }

  private val methodChannel = MethodChannel(messenger, "app.calls/audio_route")
  private val eventChannel = EventChannel(messenger, "app.calls/audio_route/routeChanged")
  private var eventSink: EventChannel.EventSink? = null
  private val receiver = object : BroadcastReceiver() {
    override fun onReceive(ctx: Context?, intent: Intent?) {
      debounceEmit()
    }
  }
  private val handler = Handler(Looper.getMainLooper())
  private val emitRunnable = Runnable { emitRouteInfoIfNeeded() }
  private var lastRoute: Map<String, Any?>? = null

  init {
    methodChannel.setMethodCallHandler { call, result ->
      when (call.method) {
        "getRouteInfo" -> {
          result.success(AudioRouteHelper.getRouteInfo(context))
        }
        "setRoute" -> {
          val route = call.argument<String>("route") ?: "systemDefault"
          AudioRouteHelper.setRoute(context, route)
          result.success(null)
        }
        "startBluetoothSco" -> {
          AudioManagerHelper.startBluetoothSco(context)
          result.success(null)
        }
        "stopBluetoothSco" -> {
          AudioManagerHelper.stopBluetoothSco(context)
          result.success(null)
        }
        else -> result.notImplemented()
      }
    }

    eventChannel.setStreamHandler(object : EventChannel.StreamHandler {
      override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
        handler.removeCallbacks(emitRunnable)
        ContextCompat.registerReceiver(
          context,
          receiver,
          createIntentFilter(),
          ContextCompat.RECEIVER_NOT_EXPORTED,
        )
        emitRouteInfoIfNeeded(initial = true)
      }

      override fun onCancel(arguments: Any?) {
        eventSink = null
        handler.removeCallbacks(emitRunnable)
        try {
          context.unregisterReceiver(receiver)
        } catch (ignored: Exception) {
        }
        lastRoute = null
      }
    })
  }

  private fun createIntentFilter(): IntentFilter {
    val filter = IntentFilter()
    filter.addAction(AudioManager.ACTION_HEADSET_PLUG)
    filter.addAction(BluetoothAdapter.ACTION_CONNECTION_STATE_CHANGED)
    filter.addAction(AudioManager.ACTION_SCO_AUDIO_STATE_UPDATED)
    filter.addAction(AudioManager.ACTION_AUDIO_BECOMING_NOISY)
    return filter
  }

  private fun debounceEmit() {
    handler.removeCallbacks(emitRunnable)
    handler.postDelayed(emitRunnable, 200)
  }

  private fun emitRouteInfoIfNeeded(initial: Boolean = false) {
    val info = AudioRouteHelper.getRouteInfo(context)
    if (initial || info != lastRoute) {
      lastRoute = info
      eventSink?.success(info)
    }
  }
}
