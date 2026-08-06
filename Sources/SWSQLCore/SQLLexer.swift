import Foundation

/// A range-preserving scan of SQL text, shared by the statement splitter and
/// the syntax highlighter so they agree on what is a comment, a string, or a
/// live `;`.
///
/// Handles single-quoted literals (with `''` doubling), quoted identifiers
/// (with `""` doubling), line comments, nested block comments and Postgres
/// dollar-quoted strings (`$$…$$`, `$tag$…$tag$`). Ranges are in `Character`
/// offsets - the unit the editor's cursor reports - and cover the entire input
/// with no gaps.
enum SQLLexer {
    enum Kind {
        case whitespace
        case comment          // -- … or /* … */ (nested)
        case string           // '…' or a dollar-quoted body
        case quotedIdentifier // "…"
        case word             // identifier or keyword
        case number
        case semicolon        // a statement-splitting `;`
        case other            // operators and remaining punctuation
    }

    struct Segment: Equatable {
        let kind: Kind
        let range: Range<Int>
    }

    static func segments(in sql: String) -> [Segment] {
        let chars = Array(sql)
        var segments: [Segment] = []
        var i = 0

        func peek(_ offset: Int = 0) -> Character? {
            let index = i + offset
            return index < chars.count ? chars[index] : nil
        }

        /// A `$` or `$tag$` opener at `i`; returns the tag including both `$`s.
        func dollarTag() -> [Character]? {
            guard chars[i] == "$" else { return nil }
            if let first = peek(1), first.isNumber { return nil } // $1 is a parameter
            var j = i + 1
            while j < chars.count, chars[j].isLetter || chars[j].isNumber || chars[j] == "_" { j += 1 }
            guard j < chars.count, chars[j] == "$" else { return nil }
            return Array(chars[i ... j])
        }

        while i < chars.count {
            let start = i
            let c = chars[i]

            if c.isWhitespace {
                while i < chars.count, chars[i].isWhitespace { i += 1 }
                segments.append(Segment(kind: .whitespace, range: start ..< i))
                continue
            }
            if c == "-", peek(1) == "-" {
                while i < chars.count, chars[i] != "\n" { i += 1 }
                segments.append(Segment(kind: .comment, range: start ..< i))
                continue
            }
            if c == "/", peek(1) == "*" {
                var depth = 1; i += 2
                while i < chars.count, depth > 0 {
                    if chars[i] == "/", peek(1) == "*" { depth += 1; i += 2 }
                    else if chars[i] == "*", peek(1) == "/" { depth -= 1; i += 2 }
                    else { i += 1 }
                }
                segments.append(Segment(kind: .comment, range: start ..< i))
                continue
            }
            if c == "'" || c == "\"" {
                let quote = c; i += 1
                while i < chars.count {
                    if chars[i] == quote {
                        if peek(1) == quote { i += 2; continue } // doubled quote
                        i += 1; break
                    }
                    i += 1
                }
                segments.append(Segment(kind: quote == "'" ? .string : .quotedIdentifier, range: start ..< i))
                continue
            }
            if let tag = dollarTag() {
                i += tag.count
                while i < chars.count {
                    if chars[i] == "$", i + tag.count <= chars.count, Array(chars[i ..< i + tag.count]) == tag {
                        i += tag.count; break
                    }
                    i += 1
                }
                segments.append(Segment(kind: .string, range: start ..< i))
                continue
            }
            if c == ";" {
                i += 1
                segments.append(Segment(kind: .semicolon, range: start ..< i))
                continue
            }
            if c.isLetter || c == "_" {
                while i < chars.count, chars[i].isLetter || chars[i].isNumber || chars[i] == "_" { i += 1 }
                segments.append(Segment(kind: .word, range: start ..< i))
                continue
            }
            if c.isNumber || (c == "." && (peek(1)?.isNumber ?? false)) {
                while i < chars.count, chars[i].isNumber || chars[i] == "." { i += 1 }
                segments.append(Segment(kind: .number, range: start ..< i))
                continue
            }
            i += 1
            segments.append(Segment(kind: .other, range: start ..< i))
        }
        return segments
    }
}
