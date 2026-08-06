import XCTest
@testable import SWSQLCore

final class SQLHighlighterTests: XCTestCase {
    private func spans(_ sql: String) -> [(String, SQLHighlighter.Kind)] {
        let chars = Array(sql)
        return SQLHighlighter.spans(in: sql).map {
            (String(chars[$0.range.lowerBound ..< $0.range.upperBound]), $0.kind)
        }
    }

    func testKeywordsAreHighlightedCaseInsensitively() {
        let result = spans("SELECT id From users")
        XCTAssertEqual(result.filter { $0.1 == .keyword }.map(\.0), ["SELECT", "From"])
    }

    func testIdentifiersAreNotKeywords() {
        let result = spans("select id, name from users")
        XCTAssertEqual(result.filter { $0.1 == .keyword }.map(\.0), ["select", "from"])
    }

    func testStringsNumbersAndComments() {
        let result = spans("select 'it''s', 42 -- answer")
        XCTAssertEqual(result.filter { $0.1 == .string }.map(\.0), ["'it''s'"])
        XCTAssertEqual(result.filter { $0.1 == .number }.map(\.0), ["42"])
        XCTAssertEqual(result.filter { $0.1 == .comment }.map(\.0), ["-- answer"])
    }

    func testKeywordInsideStringOrCommentIsNotAKeyword() {
        let result = spans("select '/* select */ from' /* where */")
        XCTAssertEqual(result.filter { $0.1 == .keyword }.map(\.0), ["select"])
    }

    func testMultilineBlockCommentIsOneSpan() {
        let result = spans("select 1 /* line\nline */ + 2")
        XCTAssertEqual(result.filter { $0.1 == .comment }.map(\.0), ["/* line\nline */"])
    }

    func testDollarQuotedBodyIsAString() {
        let result = spans("do $fn$ select 1; $fn$")
        XCTAssertEqual(result.filter { $0.1 == .string }.map(\.0), ["$fn$ select 1; $fn$"])
    }

    func testQuotedIdentifierKeepsDefaultColor() {
        XCTAssertTrue(spans(#""select""#).isEmpty)
    }
}
