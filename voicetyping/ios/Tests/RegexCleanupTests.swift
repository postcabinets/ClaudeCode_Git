import XCTest
@testable import VoiceTyping

final class RegexCleanupTests: XCTestCase {

    let cleanup = RegexCleanup()

    func testRemovesJapaneseFillers() {
        let input = "えーっと、あの、明日のミーティングなんだけど"
        let result = cleanup.clean(input)
        XCTAssertFalse(result.contains("えーっと"))
        XCTAssertFalse(result.contains("あの"))
        XCTAssertTrue(result.contains("明日のミーティング"))
    }

    func testRemovesEnglishFillers() {
        let input = "um so like you know the meeting is tomorrow"
        let result = cleanup.clean(input)
        XCTAssertFalse(result.contains("um "))
        XCTAssertFalse(result.contains("like "))
        XCTAssertFalse(result.contains("you know "))
        XCTAssertTrue(result.contains("the meeting is tomorrow"))
    }

    func testTrimsWhitespace() {
        let input = "  hello   world  "
        let result = cleanup.clean(input)
        XCTAssertEqual(result, "hello world")
    }

    func testEmptyStringReturnsEmpty() {
        let result = cleanup.clean("")
        XCTAssertEqual(result, "")
    }

    func testPreservesNormalText() {
        let input = "明後日の15時からミーティングです"
        let result = cleanup.clean(input)
        XCTAssertEqual(result, "明後日の15時からミーティングです")
    }
}
