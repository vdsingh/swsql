import XCTest
@testable import SWSQLCore

final class ClipboardTests: XCTestCase {
    func testOSC52WrapsBase64InTheClipboardSequence() {
        XCTAssertEqual(Clipboard.osc52(for: "hi"), "\u{1b}]52;c;aGk=\u{07}")
    }

    func testOSC52EncodesUnicodeAsUTF8() {
        // "∅" is e2 88 85 in UTF-8, which is 4oiF in base64.
        XCTAssertEqual(Clipboard.osc52(for: "∅"), "\u{1b}]52;c;4oiF\u{07}")
    }

    func testOSC52OfTheEmptyStringIsStillWellFormed() {
        XCTAssertEqual(Clipboard.osc52(for: ""), "\u{1b}]52;c;\u{07}")
    }

    func testOSC52CarriesNewlinesAndTabsVerbatim() {
        let value = "a\tb\nc"
        let sequence = Clipboard.osc52(for: value)
        let base64 = sequence
            .replacingOccurrences(of: "\u{1b}]52;c;", with: "")
            .replacingOccurrences(of: "\u{07}", with: "")
        XCTAssertEqual(Data(base64Encoded: base64), Data(value.utf8))
    }
}
