package com.sip_mvp.app

import android.content.Context
import android.app.NotificationManager
import org.json.JSONArray
import org.json.JSONObject
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
          val callUuid = call.argument<String>("callUuid") ?: callId
          val isRinging = call.argument<Boolean>("isRinging") ?: true
          NotificationHelper.showIncoming(
            context,
            notificationManager,
            callId,
            from,
            displayName,
            callUuid,
            isRinging
          )
          result.success(null)
        }
        "updateIncomingState" -> {
          val callId = call.argument<String>("callId")
          val from = call.argument<String>("from")
          val displayName = call.argument<String>("displayName")
          val isRinging = call.argument<Boolean>("isRinging")
          if (callId == null || from == null || isRinging == null) {
            result.error("invalid_args", "callId/from/isRinging are required", null)
            return@setMethodCallHandler
          }
          val callUuid = call.argument<String>("callUuid")
          NotificationHelper.updateIncomingState(
            context,
            notificationManager,
            callId,
            from,
            displayName,
            callUuid,
            isRinging
          )
          result.success(null)
        }
        "acquireAudioFocus" -> {
          val callId = call.argument<String>("callId") ?: "<none>"
          AudioFocusHelper.acquire(context, callId)
          result.success(null)
        }
        "releaseAudioFocus" -> {
          AudioFocusHelper.release(context)
          result.success(null)
        }
        "readCallAction" -> {
          val action = CallActionStore.read(context)
          if (action == null) {
            result.success(null)
            return@setMethodCallHandler
          }
          val payload = mapOf(
            "call_id" to action.callId,
            "action" to action.action,
            "timestamp" to action.timestamp
          )
          result.success(payload)
        }
        "clearCallAction" -> {
          CallActionStore.clear(context)
          result.success(null)
        }
        "cancelIncoming" -> {
          val callId = call.argument<String>("callId")
          val callUuid = call.argument<String>("callUuid")
          if (callId == null) {
            result.error("invalid_args", "callId is required", null)
            return@setMethodCallHandler
          }
          NotificationHelper.cancel(notificationManager, callId)
          if (callUuid?.isNotBlank() == true && callUuid != callId) {
            NotificationHelper.cancel(notificationManager, callUuid)
          }
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
        "drainPendingCallActions" -> {
          val prefs = context.getSharedPreferences("pending_call_actions", Context.MODE_PRIVATE)
          val raw = prefs.getString("pending_call_actions", "[]") ?: "[]"
          val array = JSONArray(raw)
          val now = System.currentTimeMillis()
          val resultList = mutableListOf<Map<String, Any>>()
          for (i in 0 until array.length()) {
            val entry = array.optJSONObject(i) ?: continue
            val ts = entry.optLong("ts", 0L)
            if (now - ts > 120_000) continue
            val type = entry.optString("type")
            val callId = entry.optString("callId")
            if (type.isEmpty() || callId.isEmpty()) continue
            resultList.add(
              mapOf(
                "type" to type,
                "callId" to callId,
                "ts" to ts
              )
            )
          }
          prefs.edit().putString("pending_call_actions", "[]").commit()
          result.success(resultList)
        }
        else -> result.notImplemented()
      }
    }
  }

  private val notificationManager: NotificationManager =
      context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
}
