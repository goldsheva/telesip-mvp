package com.sip_mvp.app

import android.content.Context
import android.app.NotificationManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

class CallsNotificationBridge(
    private val context: Context,
    messenger: BinaryMessenger
) {

  companion object {
    fun register(messenger: BinaryMessenger, context: Context) {
      CallsNotificationBridge(context, messenger)
    }
  }

  init {
    MethodChannel(messenger, "app.calls/notifications").setMethodCallHandler { call, result ->
      when (call.method) {
        "showIncoming" -> {
          val callId = call.argument<String>("callId")
          val from = call.argument<String>("from")
          val displayName = call.argument<String>("displayName")
          if (callId == null || from == null) {
            result.error("invalid_args", "callId/from are required", null)
            return@setMethodCallHandler
          }
          NotificationHelper.showIncoming(
            context,
            notificationManager,
            callId,
            from,
            displayName
          )
          result.success(null)
        }
        "cancelIncoming" -> {
          val callId = call.argument<String>("callId")
          if (callId == null) {
            result.error("invalid_args", "callId is required", null)
            return@setMethodCallHandler
          }
          NotificationHelper.cancel(notificationManager, callId)
          result.success(null)
        }
        "cancelAll" -> {
          notificationManager.cancelAll()
          result.success(null)
        }
        "setEngineAlive" -> {
          val alive = call.argument<Boolean>("alive") ?: false
          EngineStateStore.setEngineAlive(context, alive)
          result.success(null)
        }
        else -> result.notImplemented()
      }
    }
  }

  private val notificationManager: NotificationManager =
      context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
}
