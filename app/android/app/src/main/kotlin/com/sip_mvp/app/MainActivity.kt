package com.sip_mvp.app

import android.content.Intent
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
  }
}
