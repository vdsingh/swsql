import XCTest
@testable import SWSQLCore

final class GridRendererTests: XCTestCase {
    private let columns = [
        ResultColumn(name: "id", typeOID: 23, typeName: "int4"),
        ResultColumn(name: "email", typeOID: 25, typeName: "text")
    ]
    private let rows: [[String?]] = [
        ["1", "a@example.com"],
        ["2", nil]
    ]

    private func makeLayout(width: Int = 60, highestRowNumber: Int = 2) -> GridLayout {
        GridLayout.make(
            columns: columns,
            rows: rows,
            availableWidth: width,
            firstColumn: 0,
            highestRowNumber: highestRowNumber
        )
    }

    private func length(_ spans: [TextSpan]) -> Int {
        spans.reduce(0) { $0 + $1.text.count }
    }

    func testEveryLineIsExactlyTheRenderedWidth() {
        let layout = makeLayout()

        XCTAssertEqual(length(GridRenderer.headerSpans(layout: layout)), layout.renderedWidth)
        XCTAssertEqual(length(GridRenderer.ruleSpans(layout: layout)), layout.renderedWidth)
        XCTAssertEqual(length(GridRenderer.fillerSpans(layout: layout)), layout.renderedWidth)
        for (index, row) in rows.enumerated() {
            let spans = GridRenderer.rowSpans(row: row, number: index + 1, layout: layout)
            XCTAssertEqual(length(spans), layout.renderedWidth, "row \(index) is misaligned")
        }
    }

    func testNullCellsAreMarkedSoTheyCanBeStyledApart() {
        let layout = makeLayout()
        let spans = GridRenderer.rowSpans(row: rows[1], number: 2, layout: layout)

        XCTAssertTrue(spans.contains { $0.role == .null })
        XCTAssertTrue(spans.contains { $0.role == .numeric }, "int columns are marked numeric")
    }

    func testSpanIdentifiersAreUniqueWithinALine() {
        let layout = makeLayout()
        let spans = GridRenderer.rowSpans(row: rows[0], number: 1, layout: layout)
        XCTAssertEqual(Set(spans.map(\.id)).count, spans.count)
    }

    func testShortRowsDoNotCrashTheRenderer() {
        let layout = makeLayout()
        let spans = GridRenderer.rowSpans(row: ["only one value"], number: 1, layout: layout)

        XCTAssertEqual(length(spans), layout.renderedWidth)
        XCTAssertTrue(spans.contains { $0.role == .null }, "the missing value reads as NULL")
    }
}
