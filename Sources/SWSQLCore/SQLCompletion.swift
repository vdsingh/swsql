import Foundation

/// One suggestion offered in the editor's completion menu.
public struct CompletionItem: Equatable {
    public enum Kind: Equatable { case keyword, table, view, column }

    /// The identifier inserted when the item is chosen, and what the typed prefix
    /// is matched against.
    public let text: String
    /// A short right-hand note, e.g. "public · table" or "users".
    public let detail: String
    public let kind: Kind

    public init(text: String, detail: String, kind: Kind) {
        self.text = text
        self.detail = detail
        self.kind = kind
    }
}

/// Computes completions for what is being typed in the SQL editor.
///
/// It works from the text on the current line up to the cursor, so it needs no
/// knowledge of the editor's internals. The caller supplies the vocabulary
/// (keywords plus tables and columns from the live catalog); this filters and
/// ranks it against the partial identifier under the cursor.
public enum SQLCompletion {
    private static func isWordCharacter(_ c: Character) -> Bool { c.isLetter || c.isNumber || c == "_" }

    /// The identifier being typed immediately before the cursor.
    public static func currentWord(inLinePrefix prefix: String) -> String {
        String(prefix.reversed().prefix { isWordCharacter($0) }.reversed())
    }

    /// The identifier qualifying the current word ("alias." → column context).
    static func qualifier(inLinePrefix prefix: String) -> String? {
        let word = currentWord(inLinePrefix: prefix)
        let beforeWord = prefix.dropLast(word.count)
        guard beforeWord.last == "." else { return nil }
        let identifier = String(beforeWord.dropLast().reversed().prefix { isWordCharacter($0) }.reversed())
        return identifier.isEmpty ? nil : identifier
    }

    /// The keyword just before the current word, for light context.
    static func precedingKeyword(inLinePrefix prefix: String, keywords: Set<String>) -> String? {
        let word = currentWord(inLinePrefix: prefix)
        let rest = prefix.dropLast(word.count)
        guard rest.last != "." else { return nil }
        let token = String(rest.reversed().drop { $0 == " " || $0 == "\t" }.prefix { isWordCharacter($0) }.reversed())
        let upper = token.uppercased()
        return keywords.contains(upper) ? upper : nil
    }

    private static let tableContextKeywords: Set<String> = ["FROM", "JOIN", "INTO", "UPDATE", "TABLE"]

    /// Filters and ranks `vocabulary` for the identifier under the cursor.
    /// Returns an empty list when no identifier is being typed (so the menu hides).
    public static func complete(linePrefix: String, vocabulary: [CompletionItem], limit: Int = 8) -> [CompletionItem] {
        let word = currentWord(inLinePrefix: linePrefix)
        guard !word.isEmpty else { return [] }
        let needle = word.lowercased()

        let isColumnContext = qualifier(inLinePrefix: linePrefix) != nil
        let keywords = Set(vocabulary.filter { $0.kind == .keyword }.map { $0.text.uppercased() })
        let isTableContext = tableContextKeywords.contains(precedingKeyword(inLinePrefix: linePrefix, keywords: keywords) ?? "")

        struct Scored { let item: CompletionItem; let prefix: Bool; let rank: Int }
        var scored: [Scored] = []
        for item in vocabulary {
            if isColumnContext, item.kind != .column { continue }
            let name = item.text.lowercased()
            let prefixMatch = name.hasPrefix(needle)
            guard prefixMatch || name.contains(needle) else { continue }
            // Don't suggest the word the user has already typed in full.
            if name == needle { continue }
            scored.append(Scored(item: item, prefix: prefixMatch, rank: kindRank(item.kind, isTableContext: isTableContext, isColumnContext: isColumnContext)))
        }

        scored.sort { a, b in
            if a.prefix != b.prefix { return a.prefix }        // prefix matches first
            if a.rank != b.rank { return a.rank < b.rank }      // then by context priority
            if a.item.text.count != b.item.text.count { return a.item.text.count < b.item.text.count } // shorter (closer) match
            return a.item.text.lowercased() < b.item.text.lowercased()
        }
        return Array(scored.prefix(limit).map(\.item))
    }

    private static func kindRank(_ kind: CompletionItem.Kind, isTableContext: Bool, isColumnContext: Bool) -> Int {
        switch kind {
        case .column: return isColumnContext ? 0 : 2
        case .table, .view: return isTableContext ? 0 : 1
        case .keyword: return 3
        }
    }
}
