import XCTest
@testable import SWSQLCore

final class DisplayTextTests: XCTestCase {
    // MARK: - wrap

    func testWrapKeepsShortTextOnOneLine() {
        XCTAssertEqual(DisplayText.wrap("short", to: 10), ["short"])
    }

    func testWrapBreaksOnSpaces() {
        XCTAssertEqual(DisplayText.wrap("the quick brown fox", to: 9), ["the quick", "brown fox"])
    }

    func testWrapHardBreaksAWordLongerThanTheWidth() {
        XCTAssertEqual(DisplayText.wrap("abcdefghij", to: 4), ["abcd", "efgh", "ij"])
        // a long URL with no spaces still fits the width exactly
        for line in DisplayText.wrap("postgres://user@really.long.host.example.com/database", to: 12) {
            XCTAssertLessThanOrEqual(line.count, 12)
        }
    }

    func testWrapNeverExceedsTheWidth() {
        let text = "Examples: postgres://user@host/db · host=db dbname=shop · mydb"
        for width in [10, 20, 40, 80] {
            for line in DisplayText.wrap(text, to: width) {
                XCTAssertLessThanOrEqual(line.count, width, "width \(width)")
            }
        }
    }

    func testWrapAlwaysReturnsAtLeastOneLine() {
        XCTAssertEqual(DisplayText.wrap("", to: 10), [""])
    }

    // MARK: - singleLine / truncate

    func testNewlinesAndTabsAreReplacedSoTheGridStaysIntact() {
        let collapsed = DisplayText.singleLine("a\nb\tc\rd")

        XCTAssertFalse(collapsed.contains("\n"))
        XCTAssertFalse(collapsed.contains("\t"))
        XCTAssertFalse(collapsed.contains("\r"))
        XCTAssertEqual(collapsed.count, 7)
    }

    func testOtherControlCharactersBecomeAVisibleMarker() {
        XCTAssertEqual(DisplayText.singleLine("a\u{0}b"), "a·b")
        XCTAssertEqual(DisplayText.singleLine("a\u{7f}b"), "a·b")
    }

    func testNonASCIITextIsLeftAlone() {
        XCTAssertEqual(DisplayText.singleLine("naïve café"), "naïve café")
    }

    func testTruncationMarksTheCut() {
        XCTAssertEqual(DisplayText.truncate("abcdef", to: 4), "abc…")
        XCTAssertEqual(DisplayText.truncate("abcdef", to: 1), "…")
        XCTAssertEqual(DisplayText.truncate("abcdef", to: 0), "")
        XCTAssertEqual(DisplayText.truncate("abc", to: 3), "abc", "an exact fit is not truncated")
    }

    func testPaddingRespectsAlignmentAndAlwaysHitsTheWidth() {
        XCTAssertEqual(DisplayText.pad("ab", to: 5, alignment: .left), "ab   ")
        XCTAssertEqual(DisplayText.pad("ab", to: 5, alignment: .right), "   ab")
        XCTAssertEqual(DisplayText.pad("abcdefgh", to: 5, alignment: .left).count, 5)
    }

    func testNullRendersAsItsOwnGlyph() {
        let cell = DisplayText.cellText(nil, width: 6, alignment: .left)

        XCTAssertTrue(cell.hasPrefix(DisplayText.nullPlaceholder))
        XCTAssertEqual(cell.count, 6)
        XCTAssertNotEqual(
            cell.trimmingCharacters(in: .whitespaces),
            "NULL",
            "an actual 'NULL' string must not look the same as SQL NULL"
        )
    }

    func testCompactCounts() {
        XCTAssertEqual(DisplayText.compactCount(-1), "")
        XCTAssertEqual(DisplayText.compactCount(0), "0")
        XCTAssertEqual(DisplayText.compactCount(999), "999")
        XCTAssertEqual(DisplayText.compactCount(1_000), "1k")
        XCTAssertEqual(DisplayText.compactCount(1_234), "1.2k")
        XCTAssertEqual(DisplayText.compactCount(1_500_000), "1.5M")
        XCTAssertEqual(DisplayText.compactCount(2_000_000_000), "2B")
    }
}
