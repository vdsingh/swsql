import XCTest
@testable import SWSQLCore

final class SQLCompletionTests: XCTestCase {
    private let vocab: [CompletionItem] = [
        CompletionItem(text: "SELECT", detail: "keyword", kind: .keyword),
        CompletionItem(text: "FROM", detail: "keyword", kind: .keyword),
        CompletionItem(text: "users", detail: "public · table", kind: .table),
        CompletionItem(text: "user_sessions", detail: "public · table", kind: .table),
        CompletionItem(text: "orders", detail: "public · table", kind: .table),
        CompletionItem(text: "email", detail: "users", kind: .column),
        CompletionItem(text: "user_id", detail: "orders", kind: .column),
    ]

    func testCurrentWord() {
        XCTAssertEqual(SQLCompletion.currentWord(inLinePrefix: "select id from us"), "us")
        XCTAssertEqual(SQLCompletion.currentWord(inLinePrefix: "select id from "), "")
        XCTAssertEqual(SQLCompletion.currentWord(inLinePrefix: "u.ema"), "ema")
    }

    func testNoWordMeansNoMenu() {
        XCTAssertEqual(SQLCompletion.complete(linePrefix: "select * from ", vocabulary: vocab), [])
    }

    func testPrefixMatchesComeFirst() {
        let items = SQLCompletion.complete(linePrefix: "select * from us", vocabulary: vocab)
        // "users" and "user_sessions" are prefix matches on "us"; "user_id" contains but isn't a prefix.
        XCTAssertEqual(items.first?.text, "users")
        XCTAssertTrue(items.map(\.text).prefix(2).contains("user_sessions"))
    }

    func testTablesAreRankedFirstAfterFrom() {
        let items = SQLCompletion.complete(linePrefix: "select * from user", vocabulary: vocab)
        XCTAssertEqual(items.first?.kind, .table)
        XCTAssertFalse(items.contains { $0.kind == .keyword && $0.text == "user" })
    }

    func testQualifiedNameCompletesOnlyColumns() {
        let items = SQLCompletion.complete(linePrefix: "select u.ema", vocabulary: vocab)
        XCTAssertEqual(items.map(\.text), ["email"])
        XCTAssertTrue(items.allSatisfy { $0.kind == .column })
    }

    func testAlreadyTypedWordIsNotSuggested() {
        let items = SQLCompletion.complete(linePrefix: "select email from users", vocabulary: vocab)
        XCTAssertFalse(items.contains { $0.text == "users" }) // exact full match dropped
    }

    func testResultsAreLimited() {
        let many = (0..<50).map { CompletionItem(text: "col\($0)", detail: "t", kind: .column) }
        XCTAssertEqual(SQLCompletion.complete(linePrefix: "x.col", vocabulary: many, limit: 5).count, 5)
    }
}
