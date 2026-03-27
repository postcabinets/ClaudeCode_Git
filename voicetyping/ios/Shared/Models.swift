import Foundation

enum OutputMode: String, CaseIterable, Codable {
    case casual
    case business
    case technical
    case raw
}

struct FormattingResult {
    let original: String
    let cleaned: String
    let mode: OutputMode
    let wasLLMFormatted: Bool
}
