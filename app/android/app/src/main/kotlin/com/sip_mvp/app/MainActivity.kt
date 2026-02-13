package com.sip_mvp.app

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.util.Log
import androidx.core.content.ContextCompat
import android.os.PowerManager
import com.sip_mvp.app.BuildConfig
import org.json.JSONObject
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
  private var debugIncomingChannel: MethodChannel? = null
  private var releaseIncomingChannel: MethodChannel? = null
  private var pendingDebugHintCheck = false
  private var pendingReleaseHintCheck = false

  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    CallLog.ensureInit(applicationContext)
    handleIncomingHintExtras(intent)
  }

  override fun onNewIntent(intent: Intent) {
    super.onNewIntent(intent)
    setIntent(intent)
    handleIncomingHintExtras(intent)
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
    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app.storage/native")
      .setMethodCallHandler { call, result ->
        when (call.method) {
          "persistPendingIncomingHint" -> {
            val recordJson = call.arguments as? String
            if (recordJson.isNullOrEmpty()) {
              result.error(
                "INVALID_ARGUMENT",
                "recordJson string is required",
                null,
              )
              return@setMethodCallHandler
            }
            try {
              PendingIncomingHintWriter.persist(applicationContext, recordJson)
              IncomingCallNotificationHelper.showIncomingNotificationFromPendingHint(this)
              result.success(null)
            } catch (error: Exception) {
              result.error(
                "WRITE_FAILED",
                "Failed to persist pending incoming hint",
                error.message,
              )
            }
          }
          "readPendingIncomingHint" -> {
            try {
              val record = PendingIncomingHintWriter.read(applicationContext)
              result.success(record)
            } catch (error: Exception) {
              result.error(
                "READ_FAILED",
                "Failed to read pending incoming hint",
                error.message,
              )
            }
          }
          "clearPendingIncomingHint" -> {
            try {
              PendingIncomingHintWriter.clear(applicationContext)
              IncomingCallNotificationHelper.cancelIncomingNotification(this)
              result.success(null)
            } catch (error: Exception) {
              result.error(
                "CLEAR_FAILED",
                "Failed to clear pending incoming hint",
                error.message,
              )
            }
          }
          else -> result.notImplemented()
        }
      }
    releaseIncomingChannel =
      MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app.calls/incoming")
    releaseIncomingChannel?.setMethodCallHandler { call, result ->
      when (call.method) {
        "refreshIncomingNotification" -> handleReleaseNotificationRefresh(result)
        "clearPendingIncomingHint" -> handleReleasePendingHintClear(result)
        else -> result.notImplemented()
      }
    }
    if (BuildConfig.DEBUG) {
      debugIncomingChannel =
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app.debug/incoming")
      debugIncomingChannel?.setMethodCallHandler { call, result ->
        when (call.method) {
          "debugRefreshIncomingNotification" -> {
            handleDebugNotificationRefresh(result)
          }
          else -> result.notImplemented()
        }
      }
      maybeDispatchDebugHintCheck()
    }
    maybeDispatchReleaseHintCheck()
    handleIncomingHintExtras(intent)
  }

  private fun handleIncomingHintExtras(intent: Intent?) {
    if (intent == null) return
    val debugTrigger = intent.getBooleanExtra(EXTRA_DEBUG_CHECK_PENDING_HINT, false)
    if (debugTrigger) {
      val fromNotification = intent.getBooleanExtra("from_incoming_notification", false)
      Log.d(
        "DebugIncomingHint",
        "handleIncomingHintExtras debug trigger fromNotification=$fromNotification",
      )
      pendingDebugHintCheck = true
      intent.removeExtra(EXTRA_DEBUG_CHECK_PENDING_HINT)
      maybeDispatchDebugHintCheck()
    }
    val releaseTrigger = intent.getBooleanExtra(EXTRA_CHECK_PENDING_HINT, false)
    if (releaseTrigger) {
      val fromAction = intent.getBooleanExtra(
        IncomingActionReceiver.EXTRA_FROM_INCOMING_ACTION,
        false,
      )
      val actionType = intent.getStringExtra(
        IncomingActionReceiver.EXTRA_ACTION_TYPE,
      )
      val callId = intent.getStringExtra(IncomingActionReceiver.EXTRA_CALL_ID)
      Log.d(
        "IncomingHint",
        "handleIncomingHintExtras release trigger fromAction=$fromAction " +
          "action=$actionType callId=${callId ?: "<none>"}",
      )
      pendingReleaseHintCheck = true
      intent.removeExtra(EXTRA_CHECK_PENDING_HINT)
      maybeDispatchReleaseHintCheck()
    }
  }

  private fun maybeDispatchDebugHintCheck() {
    if (!pendingDebugHintCheck) {
      return
    }
    val channel = debugIncomingChannel ?: return
    pendingDebugHintCheck = false
    val methodNames = listOf(
      "debugCheckPendingIncomingHint",
      "debug_check_pending_hint",
    )
    for (method in methodNames) {
      try {
        channel.invokeMethod(method, null)
        return
      } catch (error: Exception) {
        Log.w("DebugIncomingHint", "Failed to invoke $method: $error")
      }
    }
  }

  private fun maybeDispatchReleaseHintCheck() {
    if (!pendingReleaseHintCheck) {
      return
    }
    val channel = releaseIncomingChannel ?: return
    pendingReleaseHintCheck = false
    try {
      channel.invokeMethod("checkPendingIncomingHint", null)
    } catch (error: Exception) {
      Log.w("IncomingHint", "Failed to invoke release pending hint check: $error")
    }
  }
  private fun handleDebugNotificationRefresh(result: MethodChannel.Result) {
    try {
      val parsed = parsePendingHint(PendingIncomingHintWriter.read(applicationContext))
      if (parsed == null) {
        IncomingCallNotificationHelper.cancelDebugNotification(this)
        IncomingCallNotificationHelper.cancelIncomingNotification(this)
        Log.d("DebugIncomingHint", "debug refresh notification: no pending hint")
        result.success(false)
        return
      }
      IncomingCallNotificationHelper.showDebugNotification(
        this,
        callId = parsed.first,
        from = parsed.second,
      )
      Log.d("DebugIncomingHint", "debug refresh notification: posted callId=${parsed.first}")
      result.success(true)
    } catch (error: Exception) {
      Log.w("DebugIncomingHint", "debug refresh notification failed: $error")
      result.error("DEBUG_REFRESH_FAILED", error.message, null)
    }
  }

  private fun handleReleaseNotificationRefresh(result: MethodChannel.Result) {
    try {
      val posted =
        IncomingCallNotificationHelper.showIncomingNotificationFromPendingHint(
          this,
        )
      if (!posted) {
        Log.d("IncomingHint", "release refresh notification: no pending hint")
      }
      result.success(posted)
    } catch (error: Exception) {
      Log.w("IncomingHint", "release refresh notification failed: $error")
      result.error("RELEASE_REFRESH_FAILED", error.message, null)
    }
  }

  private fun handleReleasePendingHintClear(result: MethodChannel.Result) {
    try {
      PendingIncomingHintWriter.clear(applicationContext)
      IncomingCallNotificationHelper.cancelIncomingNotification(this)
      result.success(null)
    } catch (error: Exception) {
      Log.w("IncomingHint", "clear pending hint failed: $error")
      result.error("CLEAR_PENDING_HINT_FAILED", error.message, null)
    }
  }

  private fun parsePendingHint(recordJson: String?): Pair<String?, String?>? {
    if (recordJson.isNullOrEmpty()) return null
    return try {
      val payload = JSONObject(recordJson).optJSONObject("payload")
      val callId = payload?.optString("call_id")?.takeIf { it.isNotBlank() }
      val from = payload?.optString("from")?.takeIf { it.isNotBlank() }
      Pair(callId, from)
    } catch (_: Exception) {
      null
    }
  }

  companion object {
    const val EXTRA_DEBUG_CHECK_PENDING_HINT = "debug_check_pending_hint"
    const val EXTRA_CHECK_PENDING_HINT = "check_pending_incoming_hint"
  }
}
