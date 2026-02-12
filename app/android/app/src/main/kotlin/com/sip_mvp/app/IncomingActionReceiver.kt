package com.sip_mvp.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class IncomingActionReceiver : BroadcastReceiver() {
  override fun onReceive(context: Context, intent: Intent) {
    val appContext = context.applicationContext ?: context
    CallLog.ensureInit(appContext)
    val actionType = when (intent.action) {
      ACTION_INCOMING_ANSWER -> "answer"
      ACTION_INCOMING_DECLINE -> "decline"
      else -> {
        CallLog.w(TAG, "Unknown action received: ${intent.action}")
        return
      }
    }
    val callId = intent.getStringExtra(EXTRA_CALL_ID) ?: "pending"
    val timestamp = System.currentTimeMillis()
    PendingCallActionStore.enqueue(appContext, callId, actionType, timestamp)
    IncomingCallNotificationHelper.cancelIncomingNotification(appContext)
    CallLog.d(
      TAG,
      "Stored pending action type=$actionType callId=$callId ts=$timestamp",
    )
    val startIntent = Intent(appContext, MainActivity::class.java).apply {
      putExtra(MainActivity.EXTRA_CHECK_PENDING_HINT, true)
      putExtra(EXTRA_FROM_INCOMING_ACTION, true)
      putExtra(EXTRA_ACTION_TYPE, actionType)
      putExtra(EXTRA_CALL_ID, callId)
      addFlags(
        Intent.FLAG_ACTIVITY_NEW_TASK or
          Intent.FLAG_ACTIVITY_SINGLE_TOP or
          Intent.FLAG_ACTIVITY_CLEAR_TOP,
      )
    }
    try {
      appContext.startActivity(startIntent)
      CallLog.d(TAG, "Started MainActivity from action=$actionType callId=$callId")
    } catch (error: Exception) {
      CallLog.w(TAG, "Failed to start MainActivity from action=$actionType: $error")
    }
  }

  companion object {
    private const val TAG = "IncomingHint"
    const val ACTION_INCOMING_ANSWER = "com.sip_mvp.app.action.INCOMING_ANSWER"
    const val ACTION_INCOMING_DECLINE = "com.sip_mvp.app.action.INCOMING_DECLINE"
    const val EXTRA_CALL_ID = "call_id"
    const val EXTRA_FROM_INCOMING_ACTION = "from_incoming_action"
    const val EXTRA_ACTION_TYPE = "incoming_action_type"
  }
}
