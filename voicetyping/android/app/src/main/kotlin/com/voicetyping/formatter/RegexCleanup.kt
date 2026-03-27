package com.voicetyping.formatter

class RegexCleanup {

    private val jaFillers = listOf(
        "えーっと[、,]?\\s*",
        "えーと[、,]?\\s*",
        "えー[、,]?\\s*",
        "あのー?[、,]?\\s*",
        "うーん[、,]?\\s*",
        "まあ[、,]?\\s*",
        "なんか[、,]?\\s*",
        "そのー?[、,]?\\s*",
    )

    private val enFillers = listOf(
        "\\bum+\\b[,.]?\\s*",
        "\\buh+\\b[,.]?\\s*",
        "\\blike\\b[,]?\\s+(?=\\w)",
        "\\byou know\\b[,.]?\\s*",
        "\\bso\\b[,]?\\s+(?=\\w)",
        "\\bbasically\\b[,.]?\\s*",
        "\\bactually\\b[,.]?\\s*",
        "\\bi mean\\b[,.]?\\s*",
    )

    fun clean(text: String): String {
        if (text.isBlank()) return ""

        var result = text
        (jaFillers + enFillers).forEach { pattern ->
            result = Regex(pattern, RegexOption.IGNORE_CASE).replace(result, "")
        }
        result = result.replace(Regex("\\s{2,}"), " ").trim()
        return result
    }
}
