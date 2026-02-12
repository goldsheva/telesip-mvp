package com.sip_mvp.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

/**
 * Debug-only broadcast receiver that mimics the pending incoming hint that FCM would enqueue.
 *
 * Example:
 * adb shell am broadcast -a com.sip_mvp.app.DEBUG_PENDING_INCOMING_HINT \
 *   --es payload '{"type":"incoming_call","call_id":"123","from":"Test","display_name":"Demo"}' \
 *   --ez trigger_ui true
 */
class DebugIncomingCallReceiver : BroadcastReceiver() {
  override fun onReceive(context: Context, intent: Intent) {
    CallLog.ensureInit(context)
    val action = intent.action ?: return
    if (action != ACTION_PERSIST_PENDING_HINT) {
      CallLog.w(TAG, "Ignoring unsupported action=$action")
      return
    }

    val payloadRaw = intent.getStringExtra(EXTRA_PAYLOAD)
    if (payloadRaw.isNullOrEmpty()) {
      CallLog.w(TAG, "Missing payload extra, nothing stored")
      return
    }
    val timestamp =
      intent.getStringExtra(EXTRA_TIMESTAMP)?.takeIf { it.isNotEmpty() } ?: isoTimestamp()

    val recordJson = try {
      val payload = JSONObject(payloadRaw)
      JSONObject()
        .put("timestamp", timestamp)
        .put("payload", payload)
        .toString()
    } catch (error: Exception) {
      CallLog.e(TAG, "Invalid payload JSON: $payloadRaw", error)
      return
    }

    PendingIncomingHintWriter.persist(context.applicationContext, recordJson)
    CallLog.d(TAG, "Persisted pending hint via debug receiver timestamp=$timestamp")
    val triggerUi = intent.getBooleanExtra(EXTRA_TRIGGER_UI, false)
    CallLog.d(TAG, "trigger_ui requested=$triggerUi")
    if (triggerUi && BuildConfig.DEBUG) {
      val triggerIntent = Intent(context, MainActivity::class.java).apply {
        putExtra(MainActivity.EXTRA_DEBUG_CHECK_PENDING_HINT, true)
        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
      }
      context.startActivity(triggerIntent)
      CallLog.d(TAG, "Triggered debug pending hint check via MainActivity")
    }
  }

  private fun isoTimestamp(): String {
    val formatter = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US)
    formatter.timeZone = TimeZone.getTimeZone("UTC")
    return formatter.format(Date())
  }

  companion object {
    private const val TAG = "DebugIncomingHint"
    const val ACTION_PERSIST_PENDING_HINT = "com.sip_mvp.app.DEBUG_PENDING_INCOMING_HINT"
    private const val EXTRA_PAYLOAD = "payload"
    private const val EXTRA_TIMESTAMP = "timestamp"
    const val EXTRA_TRIGGER_UI = "trigger_ui"
  }
}
