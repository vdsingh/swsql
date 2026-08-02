import Foundation

/// Decides how wide each column should be and which columns fit on screen.
///
/// Pure value logic, deliberately free of any terminal or connection dependency,
/// so the awkward cases - a single column wider than the screen, a viewport of
/// zero width, a column window scrolled past the end - are all unit testable.
public struct GridLayout: Equatable {
    public struct Column: Equatable {
        /// Index into the result set's column list.
        public var sourceIndex: Int
        public var title: String
        public var width: Int
        public var alignment: ColumnAlignment
    }

    /// The gap drawn between two columns.
    public static let separator = " │ "

    /// Never let one wide column, such as a JSON blob, push everything else off screen.
    public static let maxColumnWidth = 44
    public static let minColumnWidth = 3

    /// How many rows are inspected when measuring natural column widths. Measuring
    /// every row of a large result would cost more than it improves the layout.
    public static let sampleSize = 200

    public var columns: [Column]
    /// Index of the leftmost visible column.
    public var firstColumnIndex: Int
    public var totalColumnCount: Int
    /// Width of the row-number gutter, or 0 when there is no room for it.
    public var gutterWidth: Int

    public var isEmpty: Bool { columns.isEmpty }

    /// Index just past the last visible column.
    public var columnWindowEnd: Int { firstColumnIndex + columns.count }

    /// Total width the rendered grid occupies.
    public var renderedWidth: Int {
        let gutter = gutterWidth > 0 ? gutterWidth + GridLayout.separator.count : 0
        let bodies = columns.map(\.width).reduce(0, +)
        let gaps = max(0, columns.count - 1) * GridLayout.separator.count
        return gutter + bodies + gaps
    }

    /// Measures how wide each column would like to be.
    ///
    /// This is the expensive part of laying out a grid, and it only depends on the
    /// result set, so it is computed once when a result arrives rather than on
    /// every redraw.
    public static func naturalWidths(columns: [ResultColumn], rows: [[String?]]) -> [Int] {
        columns.indices.map { naturalWidth(of: $0, columns: columns, rows: rows) }
    }

    /// Builds a layout for the column window starting at `firstColumn`.
    ///
    /// - Parameters:
    ///   - naturalWidths: per-column preferred widths from ``naturalWidths(columns:rows:)``.
    ///   - availableWidth: characters the grid may use.
    ///   - firstColumn: leftmost column to show; clamped into range.
    ///   - highestRowNumber: largest row number that will be displayed, used to
    ///     size the gutter. Pass 0 to omit the gutter.
    public static func make(
        columns: [ResultColumn],
        naturalWidths: [Int],
        availableWidth: Int,
        firstColumn: Int,
        highestRowNumber: Int
    ) -> GridLayout {
        guard !columns.isEmpty, availableWidth > 0 else {
            return GridLayout(columns: [], firstColumnIndex: 0, totalColumnCount: columns.count, gutterWidth: 0)
        }

        let start = min(max(0, firstColumn), max(0, columns.count - 1))

        var gutterWidth = highestRowNumber > 0 ? String(highestRowNumber).count : 0
        // The gutter is a nicety; drop it before dropping actual data.
        if gutterWidth + separator.count + minColumnWidth > availableWidth {
            gutterWidth = 0
        }

        var remaining = availableWidth - (gutterWidth > 0 ? gutterWidth + separator.count : 0)

        var visible: [Column] = []
        for index in start..<columns.count {
            let natural = naturalWidths[safe: index] ?? minColumnWidth

            // Each column after the first has to pay for its separator too.
            let separatorCost = visible.isEmpty ? 0 : separator.count
            let budget = remaining - separatorCost
            if budget < minColumnWidth {
                break
            }

            let width = min(natural, budget)
            visible.append(
                Column(
                    sourceIndex: index,
                    title: columns[index].name,
                    width: width,
                    alignment: columns[index].alignment
                )
            )
            remaining -= separatorCost + width
        }

        // A single column wider than the viewport still has to be shown, clipped.
        if visible.isEmpty {
            let width = max(1, availableWidth)
            visible.append(
                Column(
                    sourceIndex: start,
                    title: columns[start].name,
                    width: width,
                    alignment: columns[start].alignment
                )
            )
            gutterWidth = 0
        }

        return GridLayout(
            columns: visible,
            firstColumnIndex: start,
            totalColumnCount: columns.count,
            gutterWidth: gutterWidth
        )
    }

    /// The width a column would like: its header, or its widest sampled value.
    static func naturalWidth(of index: Int, columns: [ResultColumn], rows: [[String?]]) -> Int {
        var width = columns[index].name.count
        for row in rows.prefix(sampleSize) {
            guard index < row.count else { continue }
            let length: Int
            if let value = row[index] {
                length = DisplayText.singleLine(value).count
            } else {
                length = DisplayText.nullPlaceholder.count
            }
            width = max(width, length)
            if width >= maxColumnWidth { break }
        }
        return min(max(width, minColumnWidth), maxColumnWidth)
    }

    /// Convenience for callers that have not pre-measured the result, such as tests.
    public static func make(
        columns: [ResultColumn],
        rows: [[String?]],
        availableWidth: Int,
        firstColumn: Int,
        highestRowNumber: Int
    ) -> GridLayout {
        make(
            columns: columns,
            naturalWidths: naturalWidths(columns: columns, rows: rows),
            availableWidth: availableWidth,
            firstColumn: firstColumn,
            highestRowNumber: highestRowNumber
        )
    }
}
