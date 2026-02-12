package com.sip_mvp.app

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.util.Log
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.os.PowerManager

class MainActivity : FlutterFragmentActivity() {
  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    CallLog.ensureInit(applicationContext)
  }

  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    CallsNotificationBridge.register(flutterEngine.dartExecutor.binaryMessenger, this)
    CallsAudioRouteBridge.register(flutterEngine.dartExecutor.binaryMessenger, this)
    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app.foreground_service")
      .setMethodCallHandler { call, result ->
        val intent = Intent(this, SipForegroundService::class.java)
        when (call.method) {
          "startForegroundService" -> {
            intent.action = SipForegroundService.ACTION_START
            val needsMicrophone =
              call.argument<Boolean>("needsMicrophone") == true
            intent.putExtra(SipForegroundService.EXTRA_NEEDS_MICROPHONE, needsMicrophone)
            ContextCompat.startForegroundService(this, intent)
            result.success(null)
          }
          "stopForegroundService" -> {
            intent.action = SipForegroundService.ACTION_STOP
            startService(intent)
            result.success(null)
          }
          else -> result.notImplemented()
        }
      }
    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app.system_settings")
      .setMethodCallHandler { call, result ->
        when (call.method) {
          "openIgnoreBatteryOptimizations" -> {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
              Log.d("SystemSettings", "Battery optimization prompt not needed pre-M")
              result.success(null)
              return@setMethodCallHandler
            }
            try {
              val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)
              intent.data = Uri.parse("package:$packageName")
              startActivity(intent)
              Log.d("SystemSettings", "Opened ignore battery optimizations intent")
              result.success(null)
            } catch (error: Exception) {
              Log.d("SystemSettings", "Primary battery intent failed: $error")
              try {
                startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
                Log.d("SystemSettings", "Opened legacy battery optimization settings")
                result.success(null)
              } catch (fallback: Exception) {
                Log.d("SystemSettings", "Legacy battery intent failed: $fallback")
                try {
                  val appSettings = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                  appSettings.data = Uri.fromParts("package", packageName, null)
                  startActivity(appSettings)
                  Log.d(
                    "SystemSettings",
                    "Opened APPLICATION_DETAILS_SETTINGS fallback",
                  )
                  result.success(null)
                } catch (finalFallback: Exception) {
                  Log.d("SystemSettings", "App settings fallback failed: $finalFallback")
                  result.error(
                    "UNAVAILABLE",
                    "Battery optimizations intent failed",
                    null,
                  )
                }
              }
            }
          }
          "openAppSettings" -> {
            try {
              val appSettings = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
              appSettings.data = Uri.fromParts("package", packageName, null)
              startActivity(appSettings)
              Log.d(
                "SystemSettings",
                "Opened APPLICATION_DETAILS_SETTINGS via openAppSettings",
              )
              result.success(null)
            } catch (error: Exception) {
              Log.d("SystemSettings", "App settings fallback failed: $error")
              result.error(
                "UNAVAILABLE",
                "App settings fallback failed",
                null,
              )
            }
          }
          "isIgnoringBatteryOptimizations" -> {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
              result.success(true)
              return@setMethodCallHandler
            }
            val pm = getSystemService(PowerManager::class.java)
            val ignoring = pm?.isIgnoringBatteryOptimizations(packageName) ?: false
            result.success(ignoring)
          }
          "isRunningOnEmulator" -> {
            val fingerprint = (Build.FINGERPRINT ?: "").lowercase()
            val model = (Build.MODEL ?: "").lowercase()
            val product = (Build.PRODUCT ?: "").lowercase()
            val isEmulator =
              fingerprint.contains("generic") ||
              fingerprint.contains("vbox") ||
              fingerprint.contains("test-keys") ||
              model.contains("google_sdk") ||
              model.contains("emulator") ||
              product.contains("sdk_gphone")
            result.success(isEmulator)
          }
          else -> result.notImplemented()
        }
      }
    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app.boot_state")
      .setMethodCallHandler { call, result ->
        if (call.method == "wasBootCompleted") {
          val prefs = getSharedPreferences("app_prefs", Context.MODE_PRIVATE)
          val booted = prefs.getBoolean("sip_boot_completed", false)
          result.success(booted)
        } else {
          result.notImplemented()
        }
      }
  }
}
