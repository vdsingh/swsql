import SWSQLCore
import SwiftTUI

/// The result grid, or whatever stands in for it when there is no grid to show.
struct DataPaneView: View {
    @ObservedObject var model: AppModel
    let layout: ScreenLayout

    @ViewBuilder
    var body: some View {
        if let error = model.queryError {
            ErrorPaneView(error: error, layout: layout)
        } else if let result = model.result, result.returnsRows {
            GridView(model: model, result: result, layout: layout)
        } else if let result = model.result {
            CommandResultView(result: result, layout: layout)
        } else {
            PlaceholderView(model: model, layout: layout)
        }
    }
}

/// The table itself: a pinned header over a scrolling body.
///
/// Every row of the page is a button, which is what makes the arrow keys work:
/// focusing a row asks the enclosing `ScrollView` to bring it into view, so the
/// grid scrolls by itself. Only one page is built at a time, because a control
/// per row does not scale to very large results.
struct GridView: View {
    @ObservedObject var model: AppModel
    let result: QueryResult
    let layout: ScreenLayout

    var body: some View {
        // Measured once per redraw and handed down; every row shares it.
        let grid = gridLayout
        let rows = model.pageRange

        return VStack(alignment: .leading, spacing: 0) {
            SpanLine(spans: GridRenderer.headerSpans(layout: grid))
            SpanLine(spans: GridRenderer.ruleSpans(layout: grid))
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(rows), id: \.self) { index in
                        rowView(at: index, grid: grid)
                    }
                    emptyNotice(grid: grid, isEmpty: rows.isEmpty)
                }
            }
            .frame(width: Extended(layout.mainWidth), height: Extended(layout.gridRowCapacity))
        }
    }

    private var gridLayout: GridLayout {
        GridLayout.make(
            columns: result.columns,
            naturalWidths: model.naturalColumnWidths,
            availableWidth: layout.mainWidth,
            firstColumn: model.columnOffset,
            highestRowNumber: model.pageRange.upperBound
        )
    }

    private func rowView(at index: Int, grid: GridLayout) -> some View {
        Button(
            action: { model.openRowDetail(row: index) },
            hover: { model.focusRow(index) },
            label: {
                SpanLine(
                    spans: GridRenderer.rowSpans(
                        row: result.rows[index],
                        number: index + 1,
                        layout: grid
                    )
                )
            }
        )
    }

    @ViewBuilder
    private func emptyNotice(grid: GridLayout, isEmpty: Bool) -> some View {
        if isEmpty {
            Text(DisplayText.pad(" the query returned no rows", to: grid.renderedWidth, alignment: .left))
                .foregroundColor(Theme.dim)
        }
    }
}

/// Renders one line of spans, each in its own colour.
struct SpanLine: View {
    let spans: [TextSpan]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(spans) { span in
                Text(span.text).foregroundColor(Theme.color(for: span.role))
            }
        }
    }
}

/// The row of buttons under the main pane: paging, column scrolling and pane
/// switching. Always present, whichever pane is open.
struct ControlsRow: View {
    @ObservedObject var model: AppModel
    let width: Int

    var body: some View {
        HStack(spacing: 1) {
            Text(" ")
            // In an auxiliary pane the way back to the grid comes first, because it
            // is the first control the keyboard reaches from the pane above.
            backToRowsButton
            Button("⇟", action: { model.nextPage() })
            Button("⇞", action: { model.previousPage() })
            Button("◀", action: { model.scrollColumns(by: -1) })
            Button("▶", action: { model.scrollColumns(by: 1) })
            Button("Struct", action: { model.toggleStructure() })
            Button("Hist", action: { model.toggleHistory() })
            Button("?", action: { model.toggleHelp() })
            if model.isRunning {
                Button("Cancel", action: { model.cancel() }).foregroundColor(Theme.warning)
            } else if model.isDisconnected {
                Button("Reconnect", action: { model.start() }).foregroundColor(Theme.warning)
                Button("Edit URL", action: { model.reconfigure() })
            } else {
                Text(position).foregroundColor(Theme.dim)
            }
        }
    }

    @ViewBuilder
    private var backToRowsButton: some View {
        if model.pane != .data {
            Button("Rows", action: { model.returnToData() })
        }
    }

    /// Where the user currently is, so scrolling and paging have a readout.
    private var position: String {
        guard let result = model.result, result.returnsRows else { return "" }
        let columns = "cols \(model.columnOffset + 1)/\(result.columns.count)"
        guard !result.rows.isEmpty else { return "no rows  \(columns)" }

        let range = model.pageRange
        var parts: [String] = []
        if model.hasMorePages {
            parts.append("rows \(range.lowerBound + 1)-\(range.upperBound)/\(result.rows.count)")
        } else {
            parts.append("\(result.rows.count) \(result.rows.count == 1 ? "row" : "rows")")
        }
        parts.append(columns)
        return parts.joined(separator: "  ")
    }
}

/// A statement that changed something rather than returning rows.
struct CommandResultView: View {
    let result: QueryResult
    let layout: ScreenLayout

    var body: some View {
        let headerLines = 1 + (result.affectedRows == nil ? 0 : 1)
        let notices = Array(result.notices.prefix(max(0, layout.paneContentHeight - headerLines)))

        return VStack(alignment: .leading, spacing: 0) {
            Text(" \(result.commandTag.isEmpty ? "OK" : result.commandTag)")
                .foregroundColor(Theme.success)
                .bold()
            affectedRowsLine
            ForEach(notices.indexed) { notice in
                Text(" \(DisplayText.truncate(DisplayText.singleLine(notice.value), to: max(1, layout.mainWidth - 2)))")
                    .foregroundColor(Theme.warning)
            }
            Filler(height: layout.paneContentHeight - headerLines - notices.count, width: layout.mainWidth)
        }
    }

    @ViewBuilder
    private var affectedRowsLine: some View {
        if let affected = result.affectedRows {
            Text(" \(affected) \(affected == 1 ? "row" : "rows") affected").foregroundColor(Theme.dim)
        }
    }
}

/// The server's own account of what went wrong, field by field.
struct ErrorPaneView: View {
    let error: PostgresError
    let layout: ScreenLayout

    var body: some View {
        let lines = Array(error.lines.prefix(layout.paneContentHeight))

        return VStack(alignment: .leading, spacing: 0) {
            ForEach(lines.indexed) { line in
                Text(" " + DisplayText.truncate(DisplayText.singleLine(line.value), to: max(1, layout.mainWidth - 2)))
                    .foregroundColor(line.id == 0 ? Theme.failure : Theme.dim)
            }
            Filler(height: layout.paneContentHeight - lines.count, width: layout.mainWidth)
        }
    }
}

/// What the pane shows before anything has been run.
struct PlaceholderView: View {
    @ObservedObject var model: AppModel
    let layout: ScreenLayout

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(" \(message)").foregroundColor(Theme.dim)
            Filler(height: layout.paneContentHeight - 1, width: layout.mainWidth)
        }
    }

    private var message: String {
        if model.isRunning { return "running…" }
        switch model.connectionState {
        case .unconfigured: return "paste a connection URL to begin"
        case .connecting: return "connecting to the server…"
        case .failed: return "not connected"
        case .connected: return "results will appear here"
        }
    }
}

/// Blank lines that hold a pane's height steady as its contents change.
struct Filler: View {
    let height: Int
    let width: Int

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(0..<max(0, height)), id: \.self) { _ in
                Text(String(repeating: " ", count: max(1, width)))
            }
        }
    }
}
