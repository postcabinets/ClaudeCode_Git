import XCTest
@testable import VoiceTyping

final class LLMFormatterTests: XCTestCase {

    func testRawModeReturnsOriginalText() async {
        let formatter = LLMFormatter()
        let result = await formatter.format("えーっと、hello", mode: .raw)
        XCTAssertEqual(result.cleaned, "えーっと、hello")
        XCTAssertFalse(result.wasLLMFormatted)
    }

    func testEmptyTextReturnsEmpty() async {
        let formatter = LLMFormatter()
        let result = await formatter.format("", mode: .casual)
        XCTAssertEqual(result.cleaned, "")
        XCTAssertFalse(result.wasLLMFormatted)
    }

    func testFallsBackToRegexOnNetworkError() async {
        // Use invalid URL to force failure
        let settings = Settings(suiteName: "test.\(UUID().uuidString)")
        settings.proxyURL = "https://invalid.example.com/404"
        let formatter = LLMFormatter(settings: settings)

        let result = await formatter.format("えーっと、hello world", mode: .casual)
        // Should fall back to regex cleanup
        XCTAssertFalse(result.wasLLMFormatted)
        XCTAssertFalse(result.cleaned.contains("えーっと"))
    }
}
