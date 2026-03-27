package com.voicetyping.model

import android.content.Context
import android.content.SharedPreferences
import java.util.UUID

class Settings(context: Context) {

    private val prefs: SharedPreferences =
        context.getSharedPreferences("voicetyping_prefs", Context.MODE_PRIVATE)

    var selectedMode: OutputMode
        get() = OutputMode.entries.find { it.name == prefs.getString("mode", null) } ?: OutputMode.CASUAL
        set(value) = prefs.edit().putString("mode", value.name).apply()

    val proxyURL: String
        get() = prefs.getString("proxyURL", "https://asia-northeast1-voicetyping-prod.cloudfunctions.net/formatText")!!

    val deviceId: String
        get() {
            val existing = prefs.getString("deviceId", null)
            if (existing != null) return existing
            val id = UUID.randomUUID().toString()
            prefs.edit().putString("deviceId", id).apply()
            return id
        }
}
