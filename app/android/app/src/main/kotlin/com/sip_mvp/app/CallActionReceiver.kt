package com.sip_mvp.app

import android.app.ActivityManager
import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Process
import androidx.core.content.ContextCompat
import com.sip_mvp.app.CallLog

class CallActionReceiver : BroadcastReceiver() {
  companion object {
    const val ACTION_ANSWER = "com.sip_mvp.app.ACTION_ANSWER"
    const val ACTION_DECLINE = "com.sip_mvp.app.ACTION_DECLINE"
  }

  override fun onReceive(context: Context, intent: Intent) {
    CallLog.ensureInit(context)
    val callId = intent.getStringExtra("call_id") ?: return
    val actionType = when (intent.action) {
      ACTION_ANSWER -> "answer"
      ACTION_DECLINE -> "decline"
      else -> return
    }
    val notificationManager =
      context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
    val callUuid = intent.getStringExtra("call_uuid")
    val importance = try {
      (context.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager)
        ?.runningAppProcesses
        ?.firstOrNull { it.pid == Process.myPid() }
        ?.importance
    } catch (_: Exception) {
      null
    }
    CallLog.d(
      "CALLS_ACTION",
      "resolved action=$actionType call_id=$callId call_uuid=${callUuid ?: "<none>"} importance=$importance"
    )
    val validCallId = callId.takeIf { it.isNotBlank() && it != "<none>" }
    val validCallUuid = callUuid?.takeIf { it.isNotBlank() && it != "<none>" }
    val idsToCancel = buildSet<String> {
      validCallId?.let { add(it) }
      validCallUuid?.let { add(it) }
    }
    var cancelAttempted = 0
    var cancelSucceeded = 0
    if (idsToCancel.isNotEmpty()) {
      if (notificationManager != null) {
        cancelAttempted = idsToCancel.size
        for (id in idsToCancel) {
          try {
            NotificationHelper.cancel(context, notificationManager, id)
            cancelSucceeded += 1
          } catch (error: Throwable) {
            CallLog.w("CALLS_ACTION", "notification cancel failed action=$actionType call=$id: $error")
          }
        }
      }
      NotificationHelper.markSuppressed(idsToCancel)
    }
    if (actionType == "decline") {
      val stopIntent = Intent(context, SipForegroundService::class.java).apply {
        action = SipForegroundService.ACTION_STOP
      }
      try {
        ContextCompat.startForegroundService(context, stopIntent)
      } catch (_: Throwable) {
        try {
          context.startService(stopIntent)
        } catch (_: Throwable) {
          // best effort
        }
      }
    }
    val now = System.currentTimeMillis()
    val duplicateSuppressed = !PendingCallActionStore.enqueue(context, callId, actionType, now)
    CallLog.d(
      "CALLS_ACTION",
      "action=$actionType ids=$idsToCancel hasManager=${notificationManager != null} cancelAttempted=$cancelAttempted cancelSucceeded=$cancelSucceeded duplicateSuppressed=$duplicateSuppressed",
    )
    val primaryId = validCallId ?: validCallUuid ?: "<none>"
    CallActionStore.save(context, primaryId, actionType, System.currentTimeMillis())
    CallLog.d(
      "CALLS_ACTION",
      "action_enqueued action=$actionType call_id=$callId call_uuid=$callUuid duplicateSuppressed=$duplicateSuppressed",
    )
    val main = Intent(context, MainActivity::class.java).apply {
      putExtra("call_id", callId)
      putExtra("action", actionType)
      addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
    }
    context.startActivity(main)
  }
}
