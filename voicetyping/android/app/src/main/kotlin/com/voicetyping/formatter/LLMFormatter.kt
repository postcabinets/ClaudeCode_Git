package com.voicetyping.formatter

import com.voicetyping.model.OutputMode
import com.voicetyping.model.Settings
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import java.util.concurrent.TimeUnit

data class FormattingResult(
    val original: String,
    val cleaned: String,
    val mode: OutputMode,
    val wasLLMFormatted: Boolean,
)

class LLMFormatter(private val settings: Settings) {

    private val client = OkHttpClient.Builder()
        .connectTimeout(5, TimeUnit.SECONDS)
        .readTimeout(5, TimeUnit.SECONDS)
        .build()

    private val regexCleanup = RegexCleanup()

    suspend fun format(text: String, mode: OutputMode): FormattingResult {
        if (text.isBlank()) return FormattingResult(text, text, mode, false)
        if (mode == OutputMode.RAW) return FormattingResult(text, text, mode, false)

        return try {
            val cleaned = callProxy(text, mode)
            FormattingResult(text, cleaned, mode, true)
        } catch (_: Exception) {
            val cleaned = regexCleanup.clean(text)
            FormattingResult(text, cleaned, mode, false)
        }
    }

    private suspend fun callProxy(text: String, mode: OutputMode): String =
        withContext(Dispatchers.IO) {
            val json = JSONObject().apply {
                put("text", text)
                put("mode", mode.name.lowercase())
                put("deviceId", settings.deviceId)
            }

            val body = json.toString().toRequestBody("application/json".toMediaType())
            val request = Request.Builder()
                .url(settings.proxyURL)
                .post(body)
                .build()

            val response = client.newCall(request).execute()
            if (!response.isSuccessful) throw RuntimeException("HTTP ${response.code}")

            val responseBody = response.body?.string() ?: throw RuntimeException("Empty response")
            JSONObject(responseBody).getString("result")
        }
}
