import Foundation

/// Splits editor text into individual SQL statements so the app can run the one
/// at the cursor rather than the whole buffer.
///
/// Splitting happens at `;` outside strings, identifiers and comments (per
/// `SQLLexer`). Segments that hold only comments or whitespace are not
/// statements; their text counts as the gap after the previous statement.
public enum SQLStatementSplitter {
    public struct Statement: Equatable {
        /// The statement text, trimmed, including its `;` when one was typed.
        public let text: String
        /// Where the trimmed text sits in the original string, in `Character`
        /// offsets - the same unit as the editor's cursor offset.
        public let range: Range<Int>
    }

    public static func statements(in sql: String) -> [Statement] {
        let chars = Array(sql)
        var statements: [Statement] = []
        var start = 0           // where the current segment began
        var hasContent = false  // segment has something beyond comments/whitespace

        func closeSegment(endingAt end: Int) {
            defer { start = end; hasContent = false }
            guard hasContent else { return }
            var lower = start, upper = end
            while lower < upper, chars[lower].isWhitespace { lower += 1 }
            while upper > lower, chars[upper - 1].isWhitespace { upper -= 1 }
            statements.append(Statement(text: String(chars[lower ..< upper]), range: lower ..< upper))
        }

        for segment in SQLLexer.segments(in: sql) {
            switch segment.kind {
            case .whitespace, .comment:
                break
            case .semicolon:
                hasContent = true
                closeSegment(endingAt: segment.range.upperBound)
            case .string, .quotedIdentifier, .word, .number, .other:
                hasContent = true
            }
        }
        closeSegment(endingAt: chars.count)
        return statements
    }

    /// The statement to run for a cursor at `offset`: the one the cursor is in,
    /// otherwise the nearest one before it, otherwise the first. `nil` when the
    /// text holds no statements at all.
    public static func statement(in sql: String, atCursor offset: Int) -> Statement? {
        let all = statements(in: sql)
        if let containing = all.first(where: { $0.range.contains(offset) }) {
            return containing
        }
        if let before = all.last(where: { $0.range.upperBound <= offset }) {
            return before
        }
        return all.first
    }
}
