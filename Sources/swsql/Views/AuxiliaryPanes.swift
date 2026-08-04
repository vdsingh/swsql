import SWSQLCore
import SwiftTUI

/// Column definitions for the relation selected in the sidebar, rendered with the
/// same grid machinery as query results.
struct StructurePaneView: View {
    @ObservedObject var model: AppModel
    let layout: ScreenLayout

    var body: some View {
        let structure = model.structureColumns.asResult()
        let grid = GridLayout.make(
            columns: structure.columns,
            rows: structure.rows,
            availableWidth: layout.mainWidth,
            firstColumn: 0,
            highestRowNumber: structure.rows.count
        )
        let visible = structure.rows.prefix(max(0, layout.auxiliaryCapacity - 2))

        return VStack(alignment: .leading, spacing: 0) {
            Text(DisplayText.pad(" \(title)", to: layout.mainWidth, alignment: .left))
                .foregroundColor(Theme.accent)
                .bold()
            SpanLine(spans: GridRenderer.headerSpans(layout: grid))
            SpanLine(spans: GridRenderer.ruleSpans(layout: grid))
            ForEach(Array(visible).indexed) { row in
                SpanLine(spans: GridRenderer.rowSpans(row: row.value, number: row.id + 1, layout: grid))
            }
            Filler(height: layout.auxiliaryCapacity - 2 - visible.count, width: layout.mainWidth)
        }
    }

    private var title: String {
        guard let object = model.selectedObject else { return "Structure" }
        return "\(object.kind.label)  \(object.schema).\(object.name)"
    }
}

/// One record shown vertically, which is the only sane way to read a wide row.
struct RowDetailPaneView: View {
    @ObservedObject var model: AppModel
    let layout: ScreenLayout

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(DisplayText.pad(" row \(model.focusedRow + 1) of \(model.rowCount)", to: layout.mainWidth, alignment: .left))
                .foregroundColor(Theme.accent)
                .bold()
            ForEach(fields.indexed) { field in
                SpanLine(spans: field.value)
            }
            Filler(height: layout.auxiliaryCapacity - fields.count, width: layout.mainWidth)
        }
    }

    private var fields: [[TextSpan]] {
        guard
            let result = model.result,
            result.returnsRows,
            model.focusedRow < result.rows.count
        else { return [] }

        let row = result.rows[model.focusedRow]
        let nameWidth = min(24, max(8, result.columns.map(\.name.count).max() ?? 8))
        let valueWidth = max(1, layout.mainWidth - nameWidth - 4)

        return result.columns.prefix(layout.auxiliaryCapacity).enumerated().map { index, column in
            let value = row[safe: index] ?? nil
            return [
                TextSpan(id: 0, text: " " + DisplayText.pad(column.name, to: nameWidth, alignment: .left), role: .header),
                TextSpan(id: 1, text: GridLayout.separator, role: .separator),
                TextSpan(
                    id: 2,
                    text: DisplayText.cellText(value, width: valueWidth, alignment: .left),
                    role: value == nil ? .null : .value
                )
            ]
        }
    }
}

/// Previously run statements. Re-running from here works around the fact that
/// SwiftTUI's text field cannot be pre-filled with recalled text.
struct HistoryPaneView: View {
    @ObservedObject var model: AppModel
    let layout: ScreenLayout

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(DisplayText.pad(" History", to: layout.mainWidth, alignment: .left))
                .foregroundColor(Theme.accent)
                .bold()
            ForEach(entries.indexed) { entry in
                Button(
                    action: { model.recall(at: entry.id) },
                    label: {
                        Text(" " + DisplayText.pad(DisplayText.singleLine(entry.value), to: max(1, layout.mainWidth - 1), alignment: .left))
                    }
                )
            }
            emptyNotice
            Filler(
                height: layout.auxiliaryCapacity - entries.count - (entries.isEmpty ? 1 : 0),
                width: layout.mainWidth
            )
        }
    }

    private var entries: [String] {
        Array(model.history.prefix(layout.auxiliaryCapacity))
    }

    @ViewBuilder
    private var emptyNotice: some View {
        if entries.isEmpty {
            Text(" nothing run yet").foregroundColor(Theme.dim)
        }
    }
}

/// Key bindings and the handful of behaviours worth stating outright.
struct HelpPaneView: View {
    @ObservedObject var model: AppModel
    let layout: ScreenLayout

    private static let topics: [(String, String)] = [
        ("↑ ↓ ← →", "move between the sidebar, the prompt, result rows and the buttons"),
        ("⏎", "run the statement in the prompt, open a table, or inspect a row"),
        ("⌫", "delete the last character typed"),
        ("Cancel", "appears while a statement runs; asks the server to abort it"),
        ("^C  ^D", "quit"),
        ("/ field", "filter the object list, then press ⏎"),
        ("Rows", "return to the result grid from any other pane"),
        ("◀ ▶", "scroll the grid one column at a time"),
        ("⇞ ⇟", "previous and next page of a large result"),
        ("Struct", "column types, defaults and keys for the selected table"),
        ("Hist", "re-run an earlier statement"),
        ("d", "in the connection switcher, remove the highlighted connection")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(DisplayText.pad(" swsql  ·  a PostgreSQL client for the terminal", to: layout.mainWidth, alignment: .left))
                .foregroundColor(Theme.accent)
                .bold()
            ForEach(HelpPaneView.topics.indexed) { topic in
                SpanLine(spans: [
                    TextSpan(id: 0, text: " " + DisplayText.pad(topic.value.0, to: 10, alignment: .left), role: .header),
                    TextSpan(id: 1, text: GridLayout.separator, role: .separator),
                    TextSpan(
                        id: 2,
                        text: DisplayText.pad(topic.value.1, to: max(1, layout.mainWidth - 14), alignment: .left),
                        role: .value
                    )
                ])
            }
            Text(" Results are capped at \(PGConnection.defaultRowCap) rows; table previews fetch 500.")
                .foregroundColor(Theme.dim)
            Filler(height: layout.auxiliaryCapacity - HelpPaneView.topics.count - 1, width: layout.mainWidth)
        }
    }
}
