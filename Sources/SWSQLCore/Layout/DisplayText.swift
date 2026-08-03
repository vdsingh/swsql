import Foundation

/// Text helpers for a fixed width character grid.
///
/// Widths are counted in `Character`s because that is exactly what the renderer
/// draws: one grapheme cluster per terminal cell. Counting any other way would
/// put the padding out of step with what ends up on screen.
public enum DisplayText {
    /// Placeholder shown for SQL NULL, chosen so it cannot be confused with the
    /// four character string "NULL" stored in a text column.
    public static let nullPlaceholder = "∅"

    /// Collapses anything that would break the grid onto one line.
    ///
    /// Newlines and tabs inside values are common in real data - JSON blobs,
    /// pasted text - and a raw newline would tear a hole through the table.
    public static func singleLine(_ text: String) -> String {
        var output = String()
        output.reserveCapacity(text.count)
        for character in text {
            switch character {
            case "\n", "\r": output.append("↵")
            case "\t": output.append("→")
            default:
                if let ascii = character.asciiValue, ascii < 0x20 || ascii == 0x7F {
                    output.append("·")
                } else {
                    output.append(character)
                }
            }
        }
        return output
    }

    /// Wraps `text` into lines no wider than `width`, breaking on spaces where it
    /// can and hard-breaking any single word longer than `width` (a long URL, say).
    /// Control characters and embedded newlines are first flattened, then re-wrapped,
    /// so the result is always exactly `width`-safe. Returns at least one line.
    public static func wrap(_ text: String, to width: Int) -> [String] {
        guard width > 0 else { return [""] }
        let words = singleLine(text).split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        var lines: [String] = []
        var current = ""
        for original in words {
            var word = original
            while word.count > width {
                if !current.isEmpty { lines.append(current); current = "" }
                lines.append(String(word.prefix(width)))
                word = String(word.dropFirst(width))
            }
            if word.isEmpty { continue }
            if current.isEmpty {
                current = word
            } else if current.count + 1 + word.count <= width {
                current += " " + word
            } else {
                lines.append(current)
                current = word
            }
        }
        if !current.isEmpty { lines.append(current) }
        return lines.isEmpty ? [""] : lines
    }

    /// Shortens to `width`, marking the cut with an ellipsis.
    public static func truncate(_ text: String, to width: Int) -> String {
        guard width > 0 else { return "" }
        guard text.count > width else { return text }
        if width == 1 { return "…" }
        return String(text.prefix(width - 1)) + "…"
    }

    public static func pad(_ text: String, to width: Int, alignment: ColumnAlignment) -> String {
        let clipped = truncate(text, to: width)
        let padding = max(0, width - clipped.count)
        guard padding > 0 else { return clipped }
        let spaces = String(repeating: " ", count: padding)
        return alignment == .right ? spaces + clipped : clipped + spaces
    }

    /// A short, approximate row count for narrow columns: 1234 becomes "1.2k".
    /// Returns an empty string for the -1 that Postgres uses to mean "never analysed".
    public static func compactCount(_ count: Int) -> String {
        guard count >= 0 else { return "" }
        switch count {
        case ..<1_000:
            return String(count)
        case ..<1_000_000:
            return trimZero(Double(count) / 1_000) + "k"
        case ..<1_000_000_000:
            return trimZero(Double(count) / 1_000_000) + "M"
        default:
            return trimZero(Double(count) / 1_000_000_000) + "B"
        }
    }

    private static func trimZero(_ value: Double) -> String {
        let text = String(format: "%.1f", value)
        return text.hasSuffix(".0") ? String(text.dropLast(2)) : text
    }

    /// Prepares a raw cell value for display at a fixed width.
    public static func cellText(_ value: String?, width: Int, alignment: ColumnAlignment) -> String {
        guard let value else {
            return pad(nullPlaceholder, to: width, alignment: alignment)
        }
        return pad(singleLine(value), to: width, alignment: alignment)
    }
}
