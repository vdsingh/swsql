import XCTest
@testable import SWSQLCore

final class GridLayoutTests: XCTestCase {
    private func column(_ name: String, oid: UInt32 = 25) -> ResultColumn {
        ResultColumn(name: name, typeOID: oid, typeName: "text")
    }

    private let intOID: UInt32 = 23

    func testColumnsAreAsWideAsTheirWidestValue() {
        let layout = GridLayout.make(
            columns: [column("id"), column("email")],
            rows: [["1", "a@example.com"], ["22", "much.longer@example.com"]],
            availableWidth: 120,
            firstColumn: 0,
            highestRowNumber: 2
        )

        XCTAssertEqual(layout.columns.count, 2)
        // "id" header is wider than any value, but the minimum width wins.
        XCTAssertEqual(layout.columns[0].width, GridLayout.minColumnWidth)
        XCTAssertEqual(layout.columns[1].width, "much.longer@example.com".count)
    }

    func testWideValuesAreCappedSoOneColumnCannotTakeTheScreen() {
        let huge = String(repeating: "x", count: 500)
        let layout = GridLayout.make(
            columns: [column("blob"), column("after")],
            rows: [[huge, "visible"]],
            availableWidth: 120,
            firstColumn: 0,
            highestRowNumber: 1
        )

        XCTAssertEqual(layout.columns[0].width, GridLayout.maxColumnWidth)
        XCTAssertEqual(layout.columns.count, 2, "the capped column must leave room for the next one")
    }

    func testOnlyColumnsThatFitAreIncluded() {
        let columns = (0..<10).map { column("column\($0)") }
        let rows = [Array(repeating: "0123456789", count: 10).map { Optional($0) }]

        let layout = GridLayout.make(
            columns: columns,
            rows: rows,
            availableWidth: 40,
            firstColumn: 0,
            highestRowNumber: 1
        )

        XCTAssertLessThan(layout.columns.count, 10)
        XCTAssertLessThanOrEqual(layout.renderedWidth, 40)
    }

    func testColumnWindowStartsAtTheRequestedColumn() {
        let columns = (0..<6).map { column("c\($0)") }
        let layout = GridLayout.make(
            columns: columns,
            rows: [Array(repeating: Optional("v"), count: 6)],
            availableWidth: 80,
            firstColumn: 3,
            highestRowNumber: 1
        )

        XCTAssertEqual(layout.firstColumnIndex, 3)
        XCTAssertEqual(layout.columns.first?.sourceIndex, 3)
    }

    func testFirstColumnIsClampedIntoRange() {
        let layout = GridLayout.make(
            columns: [column("only")],
            rows: [["v"]],
            availableWidth: 40,
            firstColumn: 99,
            highestRowNumber: 1
        )

        XCTAssertEqual(layout.firstColumnIndex, 0)
    }

    func testASingleColumnWiderThanTheScreenIsStillShown() {
        let layout = GridLayout.make(
            columns: [column("wide")],
            rows: [[String(repeating: "y", count: 200)]],
            availableWidth: 6,
            firstColumn: 0,
            highestRowNumber: 1
        )

        XCTAssertEqual(layout.columns.count, 1)
        XCTAssertEqual(layout.gutterWidth, 0, "the gutter is dropped before the data is")
        XCTAssertEqual(layout.renderedWidth, 6)
    }

    func testGutterIsSizedForTheHighestRowNumber() {
        let layout = GridLayout.make(
            columns: [column("a")],
            rows: [["v"]],
            availableWidth: 40,
            firstColumn: 0,
            highestRowNumber: 1234
        )

        XCTAssertEqual(layout.gutterWidth, 4)
    }

    func testGutterIsOmittedWhenNotRequested() {
        let layout = GridLayout.make(
            columns: [column("a")],
            rows: [["v"]],
            availableWidth: 40,
            firstColumn: 0,
            highestRowNumber: 0
        )

        XCTAssertEqual(layout.gutterWidth, 0)
    }

    func testEmptyResultProducesEmptyLayout() {
        let layout = GridLayout.make(
            columns: [],
            rows: [],
            availableWidth: 80,
            firstColumn: 0,
            highestRowNumber: 0
        )

        XCTAssertTrue(layout.isEmpty)
        XCTAssertEqual(layout.renderedWidth, 0)
    }

    func testZeroWidthViewportProducesEmptyLayout() {
        let layout = GridLayout.make(
            columns: [column("a")],
            rows: [["v"]],
            availableWidth: 0,
            firstColumn: 0,
            highestRowNumber: 1
        )

        XCTAssertTrue(layout.isEmpty)
    }

    func testNaturalWidthsMatchTheInlineMeasurement() {
        let columns = [column("id", oid: intOID), column("note")]
        let rows: [[String?]] = [["1", "hello"], ["1000", nil]]

        let precomputed = GridLayout.make(
            columns: columns,
            naturalWidths: GridLayout.naturalWidths(columns: columns, rows: rows),
            availableWidth: 60,
            firstColumn: 0,
            highestRowNumber: 2
        )
        let inline = GridLayout.make(
            columns: columns,
            rows: rows,
            availableWidth: 60,
            firstColumn: 0,
            highestRowNumber: 2
        )

        XCTAssertEqual(precomputed, inline)
    }

    func testNumericColumnsAlignRight() {
        let numeric = ResultColumn(name: "n", typeOID: intOID, typeName: "int4")
        let text = ResultColumn(name: "t", typeOID: 25, typeName: "text")

        XCTAssertEqual(numeric.alignment, .right)
        XCTAssertEqual(text.alignment, .left)
    }
}
