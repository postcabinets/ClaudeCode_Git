import Foundation

final class RegexCleanup {

    private let jaFillers = [
        "えーっと[、,]?\\s*",
        "えーと[、,]?\\s*",
        "えー[、,]?\\s*",
        "あのー?[、,]?\\s*",
        "うーん[、,]?\\s*",
        "まあ[、,]?\\s*",
        "なんか[、,]?\\s*",
        "そのー?[、,]?\\s*",
    ]

    private let enFillers = [
        "\\bum+\\b[,.]?\\s*",
        "\\buh+\\b[,.]?\\s*",
        "\\blike\\b[,]?\\s+(?=\\w)",
        "\\byou know\\b[,.]?\\s*",
        "\\bso\\b[,]?\\s+(?=\\w)",
        "\\bbasically\\b[,.]?\\s*",
        "\\bactually\\b[,.]?\\s*",
        "\\bi mean\\b[,.]?\\s*",
    ]

    func clean(_ text: String) -> String {
        guard !text.isEmpty else { return "" }

        var result = text

        let allFillers = jaFillers + enFillers
        for pattern in allFillers {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                result = regex.stringByReplacingMatches(
                    in: result,
                    range: NSRange(result.startIndex..., in: result),
                    withTemplate: ""
                )
            }
        }

        // Collapse multiple spaces
        if let spaceRegex = try? NSRegularExpression(pattern: "\\s{2,}") {
            result = spaceRegex.stringByReplacingMatches(
                in: result,
                range: NSRange(result.startIndex..., in: result),
                withTemplate: " "
            )
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
