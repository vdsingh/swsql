import Foundation

/// A practical SQL pretty-printer.
///
/// It tokenizes first - respecting string literals, quoted identifiers and
/// comments - so their contents are never altered, then re-lays the tokens out:
/// keywords are upper-cased, each major clause starts a new line, the items of a
/// select / group / order list each get their own indented line, and a
/// subquery's body is indented. Function-call parentheses stay inline. It is
/// deliberately simple and aims at readable everyday SQL rather than covering
/// every dialect corner.
public enum SQLFormatter {
    public static func format(_ sql: String) -> String {
        let tokens = tokenize(sql)
        guard !tokens.isEmpty else { return sql }
        return render(tokens)
    }

    // MARK: - Tokens

    enum Token: Equatable {
        case word(String)     // a keyword or identifier, original case
        case string(String)   // a quoted literal or quoted identifier, verbatim
        case number(String)
        case comment(String)  // -- … or /* … */, verbatim
        case op(String)       // = <> <= >= || :: etc.
        case punct(Character)  // ( ) , ; .
    }

    /// Keywords that are upper-cased. Function names are deliberately absent so
    /// `count(*)` keeps its case.
    static let keywords: Set<String> = [
        "SELECT", "FROM", "WHERE", "AND", "OR", "NOT", "NULL", "AS", "ON", "IN", "IS",
        "LIKE", "ILIKE", "BETWEEN", "JOIN", "LEFT", "RIGHT", "INNER", "OUTER", "FULL",
        "CROSS", "NATURAL", "USING", "GROUP", "BY", "ORDER", "HAVING", "LIMIT", "OFFSET",
        "UNION", "ALL", "INTERSECT", "EXCEPT", "DISTINCT", "INSERT", "INTO", "VALUES",
        "UPDATE", "SET", "DELETE", "RETURNING", "WITH", "CASE", "WHEN", "THEN", "ELSE",
        "END", "ASC", "DESC", "EXISTS", "ANY", "TRUE", "FALSE", "COALESCE",
    ]

    /// Keywords that begin a new line (a clause boundary).
    static let clauseStarters: Set<String> = [
        "SELECT", "FROM", "WHERE", "GROUP", "ORDER", "HAVING", "LIMIT", "OFFSET",
        "UNION", "INTERSECT", "EXCEPT", "VALUES", "RETURNING", "INSERT", "UPDATE",
        "DELETE", "SET", "WITH", "JOIN", "LEFT", "RIGHT", "INNER", "FULL", "CROSS", "NATURAL",
    ]

    /// Words that precede JOIN and should stay on its line.
    static let joinModifiers: Set<String> = ["LEFT", "RIGHT", "INNER", "OUTER", "FULL", "CROSS", "NATURAL"]

    static func tokenize(_ sql: String) -> [Token] {
        var tokens: [Token] = []
        let scalars = Array(sql)
        var i = 0

        func peek(_ offset: Int = 0) -> Character? {
            let index = i + offset
            return index < scalars.count ? scalars[index] : nil
        }

        while i < scalars.count {
            let c = scalars[i]

            if c.isWhitespace { i += 1; continue }

            // Line comment
            if c == "-", peek(1) == "-" {
                var text = ""
                while i < scalars.count, scalars[i] != "\n" { text.append(scalars[i]); i += 1 }
                tokens.append(.comment(text))
                continue
            }
            // Block comment
            if c == "/", peek(1) == "*" {
                var text = "/*"; i += 2
                while i < scalars.count {
                    if scalars[i] == "*", peek(1) == "/" { text += "*/"; i += 2; break }
                    text.append(scalars[i]); i += 1
                }
                tokens.append(.comment(text))
                continue
            }
            // String literal or quoted identifier - keep the doubled-quote escape whole
            if c == "'" || c == "\"" {
                let quote = c
                var text = String(quote); i += 1
                while i < scalars.count {
                    let ch = scalars[i]
                    text.append(ch); i += 1
                    if ch == quote {
                        if peek() == quote { text.append(quote); i += 1; continue } // escaped quote
                        break
                    }
                }
                tokens.append(.string(text))
                continue
            }
            // Number
            if c.isNumber || (c == "." && (peek(1)?.isNumber ?? false)) {
                var text = ""
                while i < scalars.count, scalars[i].isNumber || scalars[i] == "." { text.append(scalars[i]); i += 1 }
                tokens.append(.number(text))
                continue
            }
            // Word: identifier or keyword
            if c.isLetter || c == "_" {
                var text = ""
                while i < scalars.count, scalars[i].isLetter || scalars[i].isNumber || scalars[i] == "_" {
                    text.append(scalars[i]); i += 1
                }
                tokens.append(.word(text))
                continue
            }
            // Punctuation that structures the layout
            if "(),;.".contains(c) {
                tokens.append(.punct(c)); i += 1; continue
            }
            // Operators: greedily take a run of operator characters
            if "=<>!+-*/%|&~^@:".contains(c) {
                var text = ""
                while i < scalars.count, "=<>!+-*/%|&~^@:".contains(scalars[i]) { text.append(scalars[i]); i += 1 }
                tokens.append(.op(text))
                continue
            }
            // Anything else: pass through as a single-character word
            tokens.append(.word(String(c))); i += 1
        }
        return tokens
    }

    // MARK: - Rendering

    private struct Paren { let subquery: Bool }

    private static func render(_ tokens: [Token]) -> String {
        var out = ""
        var indent = 0
        var atLineStart = true
        var parens: [Paren] = []
        var previous: Token?

        func newline() {
            out += "\n" + String(repeating: "  ", count: max(0, indent))
            atLineStart = true
        }
        func emit(_ text: String, spaceBefore: Bool) {
            if !atLineStart && spaceBefore { out += " " }
            out += text
            atLineStart = false
        }

        /// Next token that isn't a comment, for lookahead.
        func nextMeaningful(after index: Int) -> Token? {
            var j = index + 1
            while j < tokens.count { if case .comment = tokens[j] {} else { return tokens[j] }; j += 1 }
            return nil
        }
        func isKeyword(_ token: Token?, _ value: String) -> Bool {
            if case .word(let w)? = token { return w.uppercased() == value }
            return false
        }

        for (index, token) in tokens.enumerated() {
            switch token {
            case .word(let raw):
                let upper = raw.uppercased()
                let keyword = SQLFormatter.keywords.contains(upper)
                if keyword, SQLFormatter.clauseStarters.contains(upper), !out.isEmpty, !atLineStart {
                    // Keep multi-word clause openers together: "DELETE FROM" and a
                    // qualified join like "LEFT OUTER JOIN".
                    let previousIsJoinModifier: Bool
                    if case .word(let w)? = previous { previousIsJoinModifier = SQLFormatter.joinModifiers.contains(w.uppercased()) }
                    else { previousIsJoinModifier = false }
                    let joinsPrevious = (upper == "FROM" && isKeyword(previous, "DELETE"))
                        || (upper == "JOIN" && previousIsJoinModifier)
                    if !joinsPrevious { newline() }
                }
                let spaceBefore = spacing(previous: previous, isWordOrValue: true)
                emit(keyword ? upper : raw, spaceBefore: spaceBefore)

            case .string(let s):
                emit(s, spaceBefore: spacing(previous: previous, isWordOrValue: true))
            case .number(let n):
                emit(n, spaceBefore: spacing(previous: previous, isWordOrValue: true))

            case .op(let o):
                emit(o, spaceBefore: spacing(previous: previous, isWordOrValue: false))

            case .comment(let text):
                emit(text, spaceBefore: !atLineStart)
                if text.hasPrefix("--") { newline() }

            case .punct(let p):
                switch p {
                case "(":
                    let subquery = isKeyword(nextMeaningful(after: index), "SELECT")
                        || isKeyword(nextMeaningful(after: index), "WITH")
                    // No space between a function name and its "(".
                    let functionCall: Bool
                    if case .word(let w)? = previous { functionCall = !SQLFormatter.keywords.contains(w.uppercased()) }
                    else { functionCall = false }
                    emit("(", spaceBefore: !atLineStart && !functionCall)
                    parens.append(Paren(subquery: subquery))
                    if subquery { indent += 1; newline() }
                case ")":
                    let paren = parens.popLast()
                    if paren?.subquery == true {
                        indent = max(0, indent - 1)
                        newline()
                    }
                    emit(")", spaceBefore: false)
                case ",":
                    emit(",", spaceBefore: false)
                    // Break the list (indented under its clause) unless we are
                    // inside a function call's parentheses.
                    if parens.isEmpty || parens.last?.subquery == true {
                        out += "\n" + String(repeating: "  ", count: indent + 1)
                        atLineStart = true
                    }
                case ";":
                    emit(";", spaceBefore: false)
                    if index != tokens.count - 1 { newline(); newline() }
                case ".":
                    emit(".", spaceBefore: false)
                default:
                    emit(String(p), spaceBefore: !atLineStart)
                }
            }
            previous = token
        }
        return out
    }

    /// Whether a value/word token wants a space before it, given the previous token.
    private static func spacing(previous: Token?, isWordOrValue: Bool) -> Bool {
        guard let previous else { return false }
        switch previous {
        case .punct("("), .punct("."): return false
        default: return true
        }
    }
}
