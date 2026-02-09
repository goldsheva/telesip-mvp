package com.sip_mvp.app

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
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
            ContextCompat.startForegroundService(this, intent)
            result.success(null)
          }
          "stopForegroundService" -> {
            intent.action = SipForegroundService.ACTION_STOP
            ContextCompat.startForegroundService(this, intent)
            result.success(null)
          }
          else -> result.notImplemented()
        }
      }
    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app.system_settings")
      .setMethodCallHandler { call, result ->
        if (call.method == "openIgnoreBatteryOptimizations") {
          if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            result.success(null)
            return@setMethodCallHandler
          }
          try {
            val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)
            intent.data = Uri.parse("package:$packageName")
            startActivity(intent)
            result.success(null)
          } catch (error: Exception) {
            try {
              startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
              result.success(null)
            } catch (fallback: Exception) {
              result.error("UNAVAILABLE", "Battery optimizations intent failed", null)
            }
          }
        } else {
          result.notImplemented()
        }
      }
  }
}
