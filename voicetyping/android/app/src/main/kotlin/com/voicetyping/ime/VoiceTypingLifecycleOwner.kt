// voicetyping/android/app/src/main/kotlin/com/voicetyping/ime/VoiceTypingLifecycleOwner.kt
package com.voicetyping.ime

import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.LifecycleRegistry

class VoiceTypingLifecycleOwner : LifecycleOwner {
    private val registry = LifecycleRegistry(this)

    init {
        registry.currentState = Lifecycle.State.RESUMED
    }

    override val lifecycle: Lifecycle = registry
}
