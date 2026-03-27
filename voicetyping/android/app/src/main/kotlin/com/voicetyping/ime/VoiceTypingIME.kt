package com.voicetyping.ime

import android.inputmethodservice.InputMethodService
import android.view.View
import androidx.compose.runtime.*
import androidx.compose.ui.platform.ComposeView
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.LifecycleRegistry
import androidx.lifecycle.setViewTreeLifecycleOwner
import androidx.savedstate.SavedStateRegistry
import androidx.savedstate.SavedStateRegistryController
import androidx.savedstate.SavedStateRegistryOwner
import androidx.savedstate.setViewTreeSavedStateRegistryOwner
import com.voicetyping.formatter.LLMFormatter
import com.voicetyping.model.OutputMode
import com.voicetyping.model.Settings
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

class VoiceTypingIME : InputMethodService(), LifecycleOwner, SavedStateRegistryOwner {

    private val lifecycleRegistry = LifecycleRegistry(this)
    private val savedStateRegistryController = SavedStateRegistryController.create(this)

    override val lifecycle: Lifecycle get() = lifecycleRegistry
    override val savedStateRegistry: SavedStateRegistry get() = savedStateRegistryController.savedStateRegistry

    private lateinit var speechManager: SpeechManager
    private lateinit var settings: Settings
    private lateinit var formatter: LLMFormatter
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    override fun onCreate() {
        super.onCreate()
        savedStateRegistryController.performRestore(null)
        lifecycleRegistry.handleLifecycleEvent(Lifecycle.Event.ON_CREATE)
        speechManager = SpeechManager(this)
        settings = Settings(this)
        formatter = LLMFormatter(settings)
    }

    override fun onCreateInputView(): View {
        val composeView = ComposeView(this).apply {
            setViewTreeLifecycleOwner(this@VoiceTypingIME)
            setViewTreeSavedStateRegistryOwner(this@VoiceTypingIME)
            setContent {
                val transcription by speechManager.transcription.collectAsState()
                val isRecording by speechManager.isRecording.collectAsState()
                var selectedMode by remember { mutableStateOf(settings.selectedMode) }
                var cleanedText by remember { mutableStateOf<String?>(null) }
                var isProcessing by remember { mutableStateOf(false) }

                KeyboardLayout(
                    transcription = transcription,
                    cleanedText = cleanedText,
                    isRecording = isRecording,
                    isProcessing = isProcessing,
                    selectedMode = selectedMode,
                    onModeSelected = {
                        selectedMode = it
                        settings.selectedMode = it
                    },
                    onMicTap = {
                        if (isRecording) {
                            val rawText = speechManager.stopRecording()
                            if (rawText.isNotBlank()) {
                                isProcessing = true
                                scope.launch {
                                    val result = formatter.format(rawText, selectedMode)
                                    cleanedText = result.cleaned
                                    isProcessing = false
                                }
                            }
                        } else {
                            cleanedText = null
                            speechManager.startRecording()
                        }
                    },
                    onInsert = {
                        val text = cleanedText ?: transcription
                        if (text.isNotBlank()) {
                            currentInputConnection?.commitText(text, 1)
                            cleanedText = null
                        }
                    },
                    onBackspace = {
                        currentInputConnection?.deleteSurroundingText(1, 0)
                    },
                    onSpace = {
                        currentInputConnection?.commitText(" ", 1)
                    },
                    onReturn = {
                        currentInputConnection?.commitText("\n", 1)
                    },
                    onSwitchKeyboard = {
                        switchToNextInputMethod(false)
                    }
                )
            }
        }

        lifecycleRegistry.handleLifecycleEvent(Lifecycle.Event.ON_RESUME)
        return composeView
    }

    override fun onDestroy() {
        super.onDestroy()
        lifecycleRegistry.handleLifecycleEvent(Lifecycle.Event.ON_DESTROY)
        scope.cancel()
    }
}
