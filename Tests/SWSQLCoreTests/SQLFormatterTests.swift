import XCTest
@testable import SWSQLCore

final class SQLFormatterTests: XCTestCase {
    func testBasicSelect() {
        let out = SQLFormatter.format("select a, b from t where a = 1")
        XCTAssertEqual(out, "SELECT a,\n  b\nFROM t\nWHERE a = 1")
    }

    func testKeywordsUppercasedFunctionsPreserved() {
        let out = SQLFormatter.format("select count(*) as n from users where active")
        XCTAssertEqual(out, "SELECT count(*) AS n\nFROM users\nWHERE active")
    }

    func testStringLiteralsAreNeverAltered() {
        // Keyword-looking words and doubled quotes inside a literal stay verbatim.
        let out = SQLFormatter.format("select 'select FROM where' as s, 'it''s' from t")
        XCTAssertTrue(out.contains("'select FROM where'"), out)
        XCTAssertTrue(out.contains("'it''s'"), out)
    }

    func testCommentsArePreserved() {
        let out = SQLFormatter.format("select 1 -- a note\nfrom t")
        XCTAssertTrue(out.contains("-- a note"), out)
    }

    func testSubqueryIsIndented() {
        let out = SQLFormatter.format("select * from (select id from t) s")
        XCTAssertEqual(out, "SELECT *\nFROM (\n  SELECT id\n  FROM t\n) s")
    }

    func testJoinsAndGroupByBreakOntoClauses() {
        let out = SQLFormatter.format(
            "select u.id, count(*) from users u left join orders o on o.user_id = u.id group by u.id order by u.id")
        // Each clause on its own line; GROUP BY / ORDER BY stay intact.
        XCTAssertTrue(out.contains("\nFROM users u"), out)
        XCTAssertTrue(out.contains("\nLEFT JOIN orders o ON o.user_id = u.id"), out)
        XCTAssertTrue(out.contains("\nGROUP BY u.id"), out)
        XCTAssertTrue(out.contains("\nORDER BY u.id"), out)
    }

    func testIdempotent() {
        let once = SQLFormatter.format("select a,b from t where a=1 and b=2")
        XCTAssertEqual(SQLFormatter.format(once), once)
    }

    func testEmptyInputIsReturnedUnchanged() {
        XCTAssertEqual(SQLFormatter.format("   "), "   ")
    }
}
