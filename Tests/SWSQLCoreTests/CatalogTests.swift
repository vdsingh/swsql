import XCTest
@testable import SWSQLCore

final class CatalogTests: XCTestCase {
    private func result(columns: [String], rows: [[String?]]) -> QueryResult {
        QueryResult(
            columns: columns.map { ResultColumn(name: $0, typeOID: 25, typeName: "text") },
            rows: rows
        )
    }

    func testObjectsAreParsedByColumnName() {
        let parsed = Catalog.parseObjects(
            result(
                columns: ["schema", "name", "kind", "estimated_rows"],
                rows: [
                    ["public", "users", "r", "1200"],
                    ["public", "active_users", "v", "-1"],
                    ["reporting", "totals", "m", "42"]
                ]
            )
        )

        XCTAssertEqual(parsed.count, 3)
        XCTAssertEqual(parsed[0], DatabaseObject(schema: "public", name: "users", kind: .table, estimatedRows: 1200))
        XCTAssertEqual(parsed[1].kind, .view)
        XCTAssertEqual(parsed[1].estimatedRows, -1)
        XCTAssertEqual(parsed[2].kind, .materializedView)
        XCTAssertEqual(parsed[2].id, "reporting.totals")
    }

    func testUnknownRelationKindsAreSkippedRatherThanGuessed() {
        let parsed = Catalog.parseObjects(
            result(columns: ["schema", "name", "kind"], rows: [["public", "seq", "S"]])
        )
        XCTAssertTrue(parsed.isEmpty)
    }

    func testFractionalRowEstimatesAreAccepted() {
        // reltuples is a float; older servers report values like "1200.0".
        let parsed = Catalog.parseObjects(
            result(
                columns: ["schema", "name", "kind", "estimated_rows"],
                rows: [["public", "users", "r", "1200.0"]]
            )
        )
        XCTAssertEqual(parsed.first?.estimatedRows, 1200)
    }

    func testColumnsAreParsedWithTheirFlags() {
        let parsed = Catalog.parseColumns(
            result(
                columns: ["name", "type", "not_null", "default_value", "is_primary_key"],
                rows: [
                    ["id", "bigint", "t", "nextval('s'::regclass)", "t"],
                    ["note", "text", "f", "", "f"]
                ]
            )
        )

        XCTAssertEqual(parsed.count, 2)
        XCTAssertEqual(parsed[0].name, "id")
        XCTAssertTrue(parsed[0].isPrimaryKey)
        XCTAssertTrue(parsed[0].isNotNull)
        XCTAssertEqual(parsed[0].defaultValue, "nextval('s'::regclass)")
        XCTAssertNil(parsed[1].defaultValue, "an empty default means there is none")
        XCTAssertFalse(parsed[1].isNotNull)
    }

    func testColumnsSQLQuotesTheRelationLiteralItIsGiven() {
        let sql = Catalog.columnsSQL(relationLiteral: "'public.users'")
        XCTAssertTrue(sql.contains("'public.users'::regclass"))
    }

    func testStructureRendersAsAResultSet() {
        let structure = [
            ColumnDescription(name: "id", type: "bigint", isNotNull: true, defaultValue: "1", isPrimaryKey: true),
            ColumnDescription(name: "note", type: "text", isNotNull: false, defaultValue: nil, isPrimaryKey: false)
        ].asResult()

        XCTAssertEqual(structure.columns.map(\.name), ["column", "type", "key", "nullable", "default"])
        XCTAssertEqual(structure.rows[0], ["id", "bigint", "pk", "not null", "1"])
        XCTAssertEqual(
            structure.rows[1],
            ["note", "text", "", "", ""],
            "absent flags render blank, not as SQL NULL"
        )
    }
}
