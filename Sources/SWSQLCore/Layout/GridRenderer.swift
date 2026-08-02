import Foundation

/// A run of characters that shares one visual treatment.
///
/// The renderer emits spans rather than finished strings so the view layer can
/// colour NULLs, numbers and separators differently while the widths stay under
/// the control of this pure, testable code.
public struct TextSpan: Equatable, Identifiable {
    public enum Role: Equatable {
        case header
        case rule
        case separator
        case gutter
        case value
        case numeric
        case null
    }

    public var id: Int
    public var text: String
    public var role: Role

    public init(id: Int, text: String, role: Role) {
        self.id = id
        self.text = text
        self.role = role
    }
}

/// Turns a result set and a layout into rows of spans.
public enum GridRenderer {
    /// Column headers, aligned the same way their values will be.
    public static func headerSpans(layout: GridLayout) -> [TextSpan] {
        var spans: [TextSpan] = []

        if layout.gutterWidth > 0 {
            spans.append(TextSpan(id: spans.count, text: String(repeating: " ", count: layout.gutterWidth), role: .gutter))
            spans.append(TextSpan(id: spans.count, text: GridLayout.separator, role: .separator))
        }

        for (offset, column) in layout.columns.enumerated() {
            if offset > 0 {
                spans.append(TextSpan(id: spans.count, text: GridLayout.separator, role: .separator))
            }
            spans.append(
                TextSpan(
                    id: spans.count,
                    text: DisplayText.pad(column.title, to: column.width, alignment: column.alignment),
                    role: .header
                )
            )
        }
        return spans
    }

    /// The horizontal rule under the header, with a join at every separator.
    public static func ruleSpans(layout: GridLayout) -> [TextSpan] {
        var text = ""

        if layout.gutterWidth > 0 {
            text += String(repeating: "─", count: layout.gutterWidth)
            text += "─┼─"
        }

        for (offset, column) in layout.columns.enumerated() {
            if offset > 0 { text += "─┼─" }
            text += String(repeating: "─", count: column.width)
        }

        return [TextSpan(id: 0, text: text, role: .rule)]
    }

    /// One data row. `number` is the 1-based row ordinal shown in the gutter.
    public static func rowSpans(row: [String?], number: Int, layout: GridLayout) -> [TextSpan] {
        var spans: [TextSpan] = []

        if layout.gutterWidth > 0 {
            spans.append(
                TextSpan(
                    id: spans.count,
                    text: DisplayText.pad(String(number), to: layout.gutterWidth, alignment: .right),
                    role: .gutter
                )
            )
            spans.append(TextSpan(id: spans.count, text: GridLayout.separator, role: .separator))
        }

        for (offset, column) in layout.columns.enumerated() {
            if offset > 0 {
                spans.append(TextSpan(id: spans.count, text: GridLayout.separator, role: .separator))
            }

            let value = row[safe: column.sourceIndex] ?? nil
            let role: TextSpan.Role
            if value == nil {
                role = .null
            } else {
                role = column.alignment == .right ? .numeric : .value
            }

            spans.append(
                TextSpan(
                    id: spans.count,
                    text: DisplayText.cellText(value, width: column.width, alignment: column.alignment),
                    role: role
                )
            )
        }
        return spans
    }

    /// A blank row of the same width, used to keep the grid a constant height
    /// so the pane below it does not jump around as results change size.
    public static func fillerSpans(layout: GridLayout) -> [TextSpan] {
        [TextSpan(id: 0, text: String(repeating: " ", count: layout.renderedWidth), role: .value)]
    }
}
