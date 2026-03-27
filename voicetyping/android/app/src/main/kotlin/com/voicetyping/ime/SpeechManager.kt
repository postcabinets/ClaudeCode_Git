package com.voicetyping.ime

import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

class SpeechManager(private val context: Context) {

    private val _transcription = MutableStateFlow("")
    val transcription: StateFlow<String> = _transcription

    private val _isRecording = MutableStateFlow(false)
    val isRecording: StateFlow<Boolean> = _isRecording

    private var speechRecognizer: SpeechRecognizer? = null
    private var accumulatedText = ""

    fun startRecording() {
        accumulatedText = ""
        _transcription.value = ""
        _isRecording.value = true
        startListening()
    }

    fun stopRecording(): String {
        _isRecording.value = false
        speechRecognizer?.stopListening()
        speechRecognizer?.destroy()
        speechRecognizer = null
        return _transcription.value
    }

    private fun startListening() {
        if (!_isRecording.value) return

        speechRecognizer?.destroy()
        speechRecognizer = SpeechRecognizer.createSpeechRecognizer(context)

        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS, 60_000L)
            putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_POSSIBLY_COMPLETE_SILENCE_LENGTH_MILLIS, 30_000L)
            putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_MINIMUM_LENGTH_MILLIS, 60_000L)
        }

        speechRecognizer?.setRecognitionListener(object : RecognitionListener {
            override fun onResults(results: Bundle?) {
                val matches = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                if (!matches.isNullOrEmpty()) {
                    accumulatedText = if (accumulatedText.isEmpty()) {
                        matches[0]
                    } else {
                        "$accumulatedText ${matches[0]}"
                    }
                    _transcription.value = accumulatedText
                }
                if (_isRecording.value) {
                    startListening()
                }
            }

            override fun onPartialResults(partialResults: Bundle?) {
                val matches = partialResults?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                if (!matches.isNullOrEmpty()) {
                    _transcription.value = if (accumulatedText.isEmpty()) {
                        matches[0]
                    } else {
                        "$accumulatedText ${matches[0]}"
                    }
                }
            }

            override fun onError(error: Int) {
                if (_isRecording.value && error != SpeechRecognizer.ERROR_CLIENT) {
                    startListening()
                }
            }

            override fun onReadyForSpeech(params: Bundle?) {}
            override fun onBeginningOfSpeech() {}
            override fun onRmsChanged(rmsdB: Float) {}
            override fun onBufferReceived(buffer: ByteArray?) {}
            override fun onEndOfSpeech() {}
            override fun onEvent(eventType: Int, params: Bundle?) {}
        })

        speechRecognizer?.startListening(intent)
    }
}
