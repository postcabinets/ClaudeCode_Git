import Foundation

final class LLMFormatter {

    private let settings: Settings
    private let regexCleanup: RegexCleanup
    private let session: URLSession

    init(settings: Settings = .shared, session: URLSession = .shared) {
        self.settings = settings
        self.regexCleanup = RegexCleanup()
        self.session = session
    }

    func format(_ text: String, mode: OutputMode) async -> FormattingResult {
        guard !text.isEmpty else {
            return FormattingResult(original: text, cleaned: text, mode: mode, wasLLMFormatted: false)
        }

        if mode == .raw {
            return FormattingResult(original: text, cleaned: text, mode: mode, wasLLMFormatted: false)
        }

        // Try LLM first
        do {
            let cleaned = try await callProxy(text: text, mode: mode)
            return FormattingResult(original: text, cleaned: cleaned, mode: mode, wasLLMFormatted: true)
        } catch {
            // Fallback to regex
            let cleaned = regexCleanup.clean(text)
            return FormattingResult(original: text, cleaned: cleaned, mode: mode, wasLLMFormatted: false)
        }
    }

    private func callProxy(text: String, mode: OutputMode) async throws -> String {
        guard let url = URL(string: settings.proxyURL) else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 5

        let body: [String: String] = [
            "text": text,
            "mode": mode.rawValue,
            "deviceId": settings.deviceId,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = json["result"] as? String else {
            throw URLError(.cannotParseResponse)
        }

        return result
    }
}
