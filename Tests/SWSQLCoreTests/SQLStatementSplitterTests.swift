import XCTest
@testable import SWSQLCore

final class SQLStatementSplitterTests: XCTestCase {
    // MARK: - Splitting

    func testSingleStatementWithoutSemicolon() {
        let statements = SQLStatementSplitter.statements(in: "select 1")
        XCTAssertEqual(statements.map(\.text), ["select 1"])
        XCTAssertEqual(statements.map(\.range), [0 ..< 8])
    }

    func testSplitsOnSemicolons() {
        let statements = SQLStatementSplitter.statements(in: "select 1; select 2;\nselect 3")
        XCTAssertEqual(statements.map(\.text), ["select 1;", "select 2;", "select 3"])
        XCTAssertEqual(statements.map(\.range), [0 ..< 9, 10 ..< 19, 20 ..< 28])
    }

    func testSemicolonInsideStringDoesNotSplit() {
        let statements = SQLStatementSplitter.statements(in: "select 'a;b'; select 2")
        XCTAssertEqual(statements.map(\.text), ["select 'a;b';", "select 2"])
    }

    func testSemicolonInsideQuotedIdentifierDoesNotSplit() {
        let statements = SQLStatementSplitter.statements(in: #"select "a;b" from t"#)
        XCTAssertEqual(statements.count, 1)
    }

    func testSemicolonInsideCommentsDoesNotSplit() {
        let sql = "select 1 -- one; two\n; /* a; b */ select 2"
        let statements = SQLStatementSplitter.statements(in: sql)
        XCTAssertEqual(statements.map(\.text), ["select 1 -- one; two\n;", "/* a; b */ select 2"])
    }

    func testSemicolonInsideDollarQuotesDoesNotSplit() {
        let sql = "create function f() returns int as $$ select 1; $$ language sql; select 2"
        let statements = SQLStatementSplitter.statements(in: sql)
        XCTAssertEqual(statements.count, 2)
        XCTAssertEqual(statements[1].text, "select 2")
    }

    func testTrailingCommentIsNotAStatement() {
        let statements = SQLStatementSplitter.statements(in: "select 1; -- done")
        XCTAssertEqual(statements.map(\.text), ["select 1;"])
    }

    func testEmptyAndWhitespaceOnlyTextHasNoStatements() {
        XCTAssertEqual(SQLStatementSplitter.statements(in: ""), [])
        XCTAssertEqual(SQLStatementSplitter.statements(in: "  \n \t"), [])
    }

    // MARK: - Picking the statement at the cursor

    private let sql = "select 1;\nselect 2;\n\nselect 3"
    // offsets:        0-8        10-18        21-28

    func testCursorInsideAStatementPicksIt() {
        XCTAssertEqual(SQLStatementSplitter.statement(in: sql, atCursor: 13)?.text, "select 2;")
    }

    func testCursorAtStatementStartPicksIt() {
        XCTAssertEqual(SQLStatementSplitter.statement(in: sql, atCursor: 21)?.text, "select 3")
    }

    func testCursorJustAfterASemicolonPicksTheStatementBefore() {
        XCTAssertEqual(SQLStatementSplitter.statement(in: sql, atCursor: 9)?.text, "select 1;")
    }

    func testCursorOnBlankLineBetweenStatementsPicksTheOneBefore() {
        XCTAssertEqual(SQLStatementSplitter.statement(in: sql, atCursor: 20)?.text, "select 2;")
    }

    func testCursorAtEndPicksTheLastStatement() {
        XCTAssertEqual(SQLStatementSplitter.statement(in: sql, atCursor: 29)?.text, "select 3")
    }

    func testCursorBeforeAnyStatementPicksTheFirst() {
        let padded = "  \n" + sql
        XCTAssertEqual(SQLStatementSplitter.statement(in: padded, atCursor: 0)?.text, "select 1;")
    }

    func testNoStatementsGivesNil() {
        XCTAssertNil(SQLStatementSplitter.statement(in: " -- just a comment", atCursor: 3))
    }
}
