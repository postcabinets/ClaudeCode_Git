package com.voicetyping

import com.voicetyping.formatter.RegexCleanup
import org.junit.Assert.*
import org.junit.Test

class RegexCleanupTest {

    private val cleanup = RegexCleanup()

    @Test
    fun removesJapaneseFillers() {
        val result = cleanup.clean("えーっと、あの、明日のミーティングなんだけど")
        assertFalse(result.contains("えーっと"))
        assertFalse(result.contains("あの"))
        assertTrue(result.contains("明日のミーティング"))
    }

    @Test
    fun removesEnglishFillers() {
        val result = cleanup.clean("um so like you know the meeting is tomorrow")
        assertFalse(result.contains("um "))
        assertFalse(result.contains("like "))
        assertFalse(result.contains("you know "))
        assertTrue(result.contains("the meeting is tomorrow"))
    }

    @Test
    fun trimsWhitespace() {
        assertEquals("hello world", cleanup.clean("  hello   world  "))
    }

    @Test
    fun emptyReturnsEmpty() {
        assertEquals("", cleanup.clean(""))
    }

    @Test
    fun preservesNormalText() {
        val input = "明後日の15時からミーティングです"
        assertEquals(input, cleanup.clean(input))
    }
}
