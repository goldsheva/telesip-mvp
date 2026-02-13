package com.sip_mvp.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class DebugIncomingActionReceiver : BroadcastReceiver() {
  override fun onReceive(context: Context, intent: Intent) {
    CallLog.ensureInit(context)
    val action = intent.action ?: return
    val actionType = when (action) {
      DebugIncomingAction.ACTION_DEBUG_INCOMING_ANSWER -> "answer"
      DebugIncomingAction.ACTION_DEBUG_INCOMING_DECLINE -> "decline"
      else -> {
        CallLog.w(TAG, "Ignoring unknown action=$action")
        return
      }
    }
    val callId = intent.getStringExtra("call_id") ?: "debug_pending"
    val timestamp = System.currentTimeMillis()

    PendingCallActionStore.enqueue(context, callId, actionType, timestamp)
    IncomingCallNotificationHelper.cancelDebugNotification(context)

    CallLog.d(
      TAG,
      "Stored pending action type=$actionType callId=$callId ts=$timestamp; notification cancelled",
    )
  }

  companion object {
    private const val TAG = "DebugIncomingHint"
  }
}
