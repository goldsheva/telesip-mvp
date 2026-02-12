package com.sip_mvp.app

import android.content.Context
import android.content.pm.ApplicationInfo
import android.util.Log

object CallLog {
  @Volatile
  private var debugFlag: Boolean? = null

  fun init(context: Context) {
    if (debugFlag == null) {
      debugFlag = (context.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0
    }
  }

  fun d(tag: String, msg: String) {
    if (debugFlag == true) {
      Log.d(tag, msg)
    }
  }

  fun w(tag: String, msg: String) {
    Log.w(tag, msg)
  }

  fun e(tag: String, msg: String, tr: Throwable? = null) {
    if (tr != null) {
      Log.e(tag, msg, tr)
    } else {
      Log.e(tag, msg)
    }
  }
}
