package com.sip_mvp.app

import android.content.Context
import android.content.SharedPreferences
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey

object PendingIncomingHintWriter {
  private const val PREFS_NAME = "sip_mvp_secure_storage"
  private const val KEY_PENDING_HINT = "sip_mvp.v1.pending_incoming_hint"

  @Volatile
  private var encryptedPrefs: SharedPreferences? = null
  private val prefsLock = Any()

  private fun prefs(context: Context): SharedPreferences {
    encryptedPrefs?.let { return it }
    synchronized(prefsLock) {
      encryptedPrefs?.let { return it }
      val appContext = context.applicationContext ?: context
      val masterKey = MasterKey.Builder(appContext)
        .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
        .build()
      val prefs = EncryptedSharedPreferences.create(
        appContext,
        PREFS_NAME,
        masterKey,
        EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
        EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
      )
      encryptedPrefs = prefs
      return prefs
    }
  }

  fun persist(context: Context, recordJson: String) {
    prefs(context)
      .edit()
      .putString(KEY_PENDING_HINT, recordJson)
      .apply()
    CallLog.d("PendingHintWriter", "persisted pending hint (${recordJson.length} bytes)")
  }

  fun read(context: Context): String? {
    return prefs(context).getString(KEY_PENDING_HINT, null)
  }

  fun clear(context: Context) {
    prefs(context)
      .edit()
      .remove(KEY_PENDING_HINT)
      .apply()
  }
}
