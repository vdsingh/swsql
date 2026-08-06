import Foundation

/// Classifies SQL text into colorable spans for the editor: keywords, string
/// literals, numbers and comments. Everything else keeps the default color.
/// Ranges are in `Character` offsets into the whole text.
public enum SQLHighlighter {
    public enum Kind: Equatable {
        case keyword, string, number, comment
    }

    public struct Span: Equatable {
        public let range: Range<Int>
        public let kind: Kind
    }

    public static func spans(in sql: String) -> [Span] {
        let chars = Array(sql)
        return SQLLexer.segments(in: sql).compactMap { segment in
            switch segment.kind {
            case .comment: return Span(range: segment.range, kind: .comment)
            case .string: return Span(range: segment.range, kind: .string)
            case .number: return Span(range: segment.range, kind: .number)
            case .word:
                let word = String(chars[segment.range.lowerBound ..< segment.range.upperBound])
                return SQLFormatter.keywords.contains(word.uppercased())
                    ? Span(range: segment.range, kind: .keyword) : nil
            case .whitespace, .quotedIdentifier, .semicolon, .other:
                return nil
            }
        }
    }
}
