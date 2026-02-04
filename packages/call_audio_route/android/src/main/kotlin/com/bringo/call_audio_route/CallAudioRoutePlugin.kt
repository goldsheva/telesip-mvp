package com.bringo.call_audio_route

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.AudioAttributes
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** A Flutter plugin that exposes basic audio-route helpers for VoIP flows. */
class CallAudioRoutePlugin : FlutterPlugin, MethodChannel.MethodCallHandler,
  EventChannel.StreamHandler, AudioManager.OnAudioFocusChangeListener {

  companion object {
    private const val CHANNEL_METHODS = "call_audio_route/methods"
    private const val CHANNEL_EVENTS = "call_audio_route/route_changes"
    private const val METHOD_SET_ROUTE = "setRoute"
    private const val METHOD_GET_ROUTE_INFO = "getRouteInfo"
    private const val BLUETOOTH_TIMEOUT_MS = 4_000L
  }

  private lateinit var applicationContext: Context
  private lateinit var audioManager: AudioManager
  private lateinit var handler: Handler

  private var methodChannel: MethodChannel? = null
  private var eventChannel: EventChannel? = null
  private var eventSink: EventChannel.EventSink? = null

  private var callModeActive = false
  private var bluetoothPending = false
  private var bluetoothTimeoutRunnable: Runnable? = null
  private var scoConnected = false

  private var audioFocusRequest: AudioFocusRequest? = null
  private var legacyFocusGranted = false
  private var focusGranted = false

  private val deviceCallback = object : AudioDeviceCallback() {
    override fun onAudioDevicesAdded(addedDevices: Array<AudioDeviceInfo>) {
      emitRouteInfo()
    }

    override fun onAudioDevicesRemoved(removedDevices: Array<AudioDeviceInfo>) {
      emitRouteInfo()
    }
  }

  private val audioIntentReceiver = object : BroadcastReceiver() {
    override fun onReceive(context: Context?, intent: Intent?) {
      when (intent?.action) {
        AudioManager.ACTION_AUDIO_BECOMING_NOISY -> {
          routeSpeaker()
          emitRouteInfo()
        }
        AudioManager.ACTION_SCO_AUDIO_STATE_UPDATED -> {
          val state = intent.getIntExtra(AudioManager.EXTRA_SCO_AUDIO_STATE, AudioManager.SCO_AUDIO_STATE_ERROR)
          when (state) {
            AudioManager.SCO_AUDIO_STATE_CONNECTED -> {
              scoConnected = true
              bluetoothPending = false
              bluetoothTimeoutRunnable?.let { handler.removeCallbacks(it) }
              bluetoothTimeoutRunnable = null
              emitRouteInfo()
            }
            AudioManager.SCO_AUDIO_STATE_DISCONNECTED,
            AudioManager.SCO_AUDIO_STATE_ERROR -> {
              scoConnected = false
              if (bluetoothPending) {
                bluetoothPending = false
                bluetoothTimeoutRunnable?.let { handler.removeCallbacks(it) }
                bluetoothTimeoutRunnable = null
                routeEarpiece()
                Log.d("CallAudioRoutePlugin", "Bluetooth SCO failed, falling back to earpiece")
                emitRouteInfo()
              }
            }
            else -> {
              // waiting for connection confirmation
            }
          }
        }
        AudioManager.ACTION_HEADSET_PLUG -> emitRouteInfo()
      }
    }
  }

  override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    applicationContext = binding.applicationContext
    audioManager = applicationContext.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    handler = Handler(Looper.getMainLooper())

    methodChannel = MethodChannel(binding.binaryMessenger, CHANNEL_METHODS).also {
      it.setMethodCallHandler(this)
    }

    eventChannel = EventChannel(binding.binaryMessenger, CHANNEL_EVENTS).also {
      it.setStreamHandler(this)
    }

    registerReceivers()
    audioManager.registerAudioDeviceCallback(deviceCallback, handler)
    emitRouteInfo()
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    methodChannel?.setMethodCallHandler(null)
    eventChannel?.setStreamHandler(null)
    methodChannel = null
    eventChannel = null
    eventSink = null

    unregisterReceivers()
    audioManager.unregisterAudioDeviceCallback(deviceCallback)
    releaseCallMode()
  }

  override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
    when (call.method) {
      METHOD_SET_ROUTE -> {
        val routeName = (call.arguments as? Map<*, *>)?.get("route") as? String
        applyRoute(routeName)
        emitRouteInfo()
        result.success(null)
      }
      METHOD_GET_ROUTE_INFO -> result.success(getRouteInfoMap())
      else -> result.notImplemented()
    }
  }

  override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
    eventSink = events
    emitRouteInfo()
  }

  override fun onCancel(arguments: Any?) {
    eventSink = null
  }

  override fun onAudioFocusChange(focusChange: Int) {
    // We do not currently do anything with focus callbacks, but could track them for logging.
  }

  private fun registerReceivers() {
    val filter = IntentFilter().apply {
      addAction(AudioManager.ACTION_AUDIO_BECOMING_NOISY)
      addAction(AudioManager.ACTION_SCO_AUDIO_STATE_UPDATED)
      addAction(AudioManager.ACTION_HEADSET_PLUG)
    }
    applicationContext.registerReceiver(audioIntentReceiver, filter)
  }

  private fun unregisterReceivers() {
    try {
      applicationContext.unregisterReceiver(audioIntentReceiver)
    } catch (_: IllegalArgumentException) {
      // Receiver was not registered.
    }
  }

  private fun applyRoute(routeName: String?) {
    val route = Route.from(routeName)
    when (route) {
      Route.SPEAKER -> {
        ensureCallMode()
        routeSpeaker()
      }
      Route.EARPIECE -> {
        ensureCallMode()
        routeEarpiece()
      }
      Route.BLUETOOTH -> {
        ensureCallMode()
        routeBluetooth()
      }
      Route.WIRED_HEADSET -> {
        ensureCallMode()
        routeWiredHeadset()
      }
      Route.SYSTEM_DEFAULT -> releaseCallMode()
    }
  }

  private fun ensureCallMode() {
    if (!callModeActive) {
      audioManager.mode = AudioManager.MODE_IN_COMMUNICATION
      requestAudioFocus()
      callModeActive = true
    }
  }

  private fun releaseCallMode() {
    if (callModeActive) {
      stopBluetoothSco()
      scoConnected = false
      audioManager.mode = AudioManager.MODE_NORMAL
      abandonAudioFocus()
      callModeActive = false
      emitRouteInfo()
    }
  }

  private fun routeSpeaker() {
    stopBluetoothSco()
    audioManager.isSpeakerphoneOn = true
  }

  private fun routeEarpiece() {
    stopBluetoothSco()
    audioManager.isSpeakerphoneOn = false
  }

  private fun routeWiredHeadset() {
    stopBluetoothSco()
    audioManager.isSpeakerphoneOn = false
  }

  private fun routeBluetooth() {
    if (!isBluetoothAvailable()) {
      routeEarpiece()
      return
    }
    audioManager.isSpeakerphoneOn = false
    bluetoothPending = true
    try {
      audioManager.startBluetoothSco()
    } catch (_: Exception) {
      Log.w("CallAudioRoutePlugin", "startBluetoothSco failed")
    }
    try {
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
        audioManager.isBluetoothScoOn = true
      } else {
        @Suppress("DEPRECATION")
        audioManager.setBluetoothScoOn(true)
      }
    } catch (_: Exception) {
      Log.w("CallAudioRoutePlugin", "Failed to enable Bluetooth SCO")
    }
    scheduleBluetoothTimeout()
  }

  private fun scheduleBluetoothTimeout() {
    bluetoothTimeoutRunnable?.let { handler.removeCallbacks(it) }
    val timeout = Runnable {
      if (bluetoothPending) {
        bluetoothPending = false
        Log.d("CallAudioRoutePlugin", "Bluetooth SCO timeout, falling back to earpiece")
        routeEarpiece()
        emitRouteInfo()
      }
    }
    bluetoothTimeoutRunnable = timeout
    handler.postDelayed(timeout, BLUETOOTH_TIMEOUT_MS)
  }

  private fun stopBluetoothSco() {
    try {
      audioManager.stopBluetoothSco()
    } catch (_: Exception) {
      Log.w("CallAudioRoutePlugin", "stopBluetoothSco failed")
    }
    try {
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
        audioManager.isBluetoothScoOn = false
      } else {
        @Suppress("DEPRECATION")
        audioManager.setBluetoothScoOn(false)
      }
    } catch (_: Exception) {
      Log.w("CallAudioRoutePlugin", "Failed to disable Bluetooth SCO")
    }
    scoConnected = false
    bluetoothTimeoutRunnable?.let { handler.removeCallbacks(it) }
    bluetoothTimeoutRunnable = null
    bluetoothPending = false
  }

  private fun requestAudioFocus() {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
      if (audioFocusRequest == null) {
        val focusRequest = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_EXCLUSIVE)
          .setAudioAttributes(
            AudioAttributes.Builder()
              .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
              .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
              .build(),
          )
          .setOnAudioFocusChangeListener(this, handler)
          .build()
        audioFocusRequest = focusRequest
      }
      focusGranted = audioManager.requestAudioFocus(audioFocusRequest!!) == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
      if (!focusGranted) {
        Log.w("CallAudioRoutePlugin", "Audio focus not granted")
      }
    } else {
      val granted = audioManager.requestAudioFocus(
        this,
        AudioManager.STREAM_VOICE_CALL,
        AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_EXCLUSIVE,
      )
      focusGranted = granted == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
      legacyFocusGranted = focusGranted
      if (!focusGranted) {
        Log.w("CallAudioRoutePlugin", "Audio focus not granted (legacy)")
      }
    }
  }

  private fun abandonAudioFocus() {
    focusGranted = false
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
      audioFocusRequest?.let {
        audioManager.abandonAudioFocusRequest(it)
        audioFocusRequest = null
      }
    } else if (legacyFocusGranted) {
      audioManager.abandonAudioFocus(this)
      legacyFocusGranted = false
    }
  }

  private fun emitRouteInfo() {
    eventSink?.success(getRouteInfoMap())
  }

  private fun getRouteInfoMap(): Map<String, Any> {
    val current = getCurrentRoute()
    val available = mutableListOf(Route.EARPIECE.value, Route.SPEAKER.value)
    if (isWiredHeadsetConnected()) available.add(Route.WIRED_HEADSET.value)
    if (isBluetoothAvailable()) available.add(Route.BLUETOOTH.value)
    if (!callModeActive) available.add(Route.SYSTEM_DEFAULT.value)

    val bluetoothConnected = isBluetoothAvailable()
    val wiredConnected = isWiredHeadsetConnected()

    return mapOf(
      "current" to current,
      "available" to available,
      "bluetoothConnected" to bluetoothConnected,
      "wiredConnected" to wiredConnected,
    )
  }

  private fun getCurrentRoute(): String {
    if (!callModeActive) {
      return Route.SYSTEM_DEFAULT.value
    }
    return when {
      scoConnected -> Route.BLUETOOTH.value
      audioManager.isSpeakerphoneOn -> Route.SPEAKER.value
      isWiredHeadsetConnected() -> Route.WIRED_HEADSET.value
      else -> Route.EARPIECE.value
    }
  }

  private fun isBluetoothAvailable(): Boolean {
    return audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS).any { device ->
      when (device.type) {
        AudioDeviceInfo.TYPE_BLUETOOTH_SCO,
        AudioDeviceInfo.TYPE_BLUETOOTH_A2DP,
        AudioDeviceInfo.TYPE_BLUETOOTH_A2DP_HEADPHONES,
        AudioDeviceInfo.TYPE_BLUETOOTH_A2DP_SPEAKER,
        AudioDeviceInfo.TYPE_BLUETOOTH_BLE -> true
        else -> false
      }
    }
  }

  private fun isWiredHeadsetConnected(): Boolean {
    return audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS).any { device ->
      when (device.type) {
        AudioDeviceInfo.TYPE_WIRED_HEADPHONES,
        AudioDeviceInfo.TYPE_WIRED_HEADSET,
        AudioDeviceInfo.TYPE_USB_HEADSET,
        AudioDeviceInfo.TYPE_USB_DEVICE -> true
        else -> false
      }
    }
  }

  private enum class Route(val value: String) {
    EARPIECE("earpiece"),
    SPEAKER("speaker"),
    BLUETOOTH("bluetooth"),
    WIRED_HEADSET("wiredHeadset"),
    SYSTEM_DEFAULT("systemDefault");

    companion object {
      fun from(value: String?): Route {
        return values().firstOrNull { it.value == value } ?: SYSTEM_DEFAULT
      }
    }
  }
}
