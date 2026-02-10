package com.sip_mvp.app

import android.Manifest
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothProfile
import android.content.Context
import android.content.pm.PackageManager
import android.media.AudioManager
import android.os.Build
import android.telephony.TelephonyManager
import android.util.Log
import androidx.core.content.ContextCompat

object AudioRouteHelper {
  private const val TAG = "AudioRouteHelper"
  private const val ROUTE_SYSTEM = "systemDefault"

  fun getRouteInfo(context: Context): Map<String, Any?> {
    val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    val telephonyManager = context.getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager
    val bluetoothConnected = isBluetoothHeadsetConnected(context)
    val wiredConnected = false // skip unreliable wired detection
    val speakerOn = audioManager.isSpeakerphoneOn
    val hasEarpiece = telephonyManager.phoneType != TelephonyManager.PHONE_TYPE_NONE

    val available = mutableListOf<String>()
    available.add("speaker")
    if (hasEarpiece) available.add("earpiece")
    if (bluetoothConnected) available.add("bluetooth")
    available.add(ROUTE_SYSTEM)

    val current = when {
      speakerOn -> "speaker"
      wiredConnected -> "wiredHeadset"
      bluetoothConnected -> "bluetooth"
      hasEarpiece -> "earpiece"
      else -> ROUTE_SYSTEM
    }

    Log.d(TAG, "routeInfo current=$current available=$available bluetoothConnected=$bluetoothConnected wiredConnected=$wiredConnected")
    return mapOf(
      "current" to current,
      "available" to available,
      "bluetoothConnected" to bluetoothConnected,
      "wiredConnected" to wiredConnected
    )
  }

  fun setRoute(context: Context, route: String) {
    val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    Log.d(TAG, "setRoute $route")
    when (route) {
      "speaker" -> {
        audioManager.isSpeakerphoneOn = true
        audioManager.mode = AudioManager.MODE_IN_COMMUNICATION
      }
      "earpiece", ROUTE_SYSTEM -> {
        audioManager.isSpeakerphoneOn = false
        audioManager.mode = AudioManager.MODE_IN_COMMUNICATION
      }
      "wiredHeadset" -> {
        audioManager.isSpeakerphoneOn = false
        audioManager.mode = AudioManager.MODE_IN_COMMUNICATION
      }
      "bluetooth" -> {
        audioManager.isSpeakerphoneOn = false
        audioManager.mode = AudioManager.MODE_IN_COMMUNICATION
      }
    }
  }

  private fun hasBtConnectPermission(context: Context): Boolean {
    return ContextCompat.checkSelfPermission(
      context,
      Manifest.permission.BLUETOOTH_CONNECT
    ) == PackageManager.PERMISSION_GRANTED
  }

  private fun isBluetoothHeadsetConnected(context: Context): Boolean {
    val adapter = BluetoothAdapter.getDefaultAdapter() ?: return false
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && !hasBtConnectPermission(context)) {
      Log.w(TAG, "BLUETOOTH_CONNECT not granted, treating as not connected")
      return false
    }
    return try {
      adapter.getProfileConnectionState(BluetoothProfile.HEADSET) == BluetoothProfile.STATE_CONNECTED
    } catch (se: SecurityException) {
      Log.w(TAG, "SecurityException while checking BT state: ${se.message}")
      false
    }
  }
}
