import Foundation

/// One named connection the user has saved: a label, the raw connection string
/// they entered (a URI, a libpq keyword string, or a bare database name), and
/// whether it points at production.
public struct SavedConnection: Codable, Equatable {
    public var name: String
    public var connectionString: String
    public var isProduction: Bool

    public init(name: String, connectionString: String, isProduction: Bool = false) {
        self.name = name
        self.connectionString = connectionString
        self.isProduction = isProduction
    }

    /// The connection string with any password obscured, for showing on screen -
    /// the switcher list, status lines. This is display only and must never be
    /// handed to libpq. Covers both the `password=…` keyword form this app writes
    /// from the setup fields and a `scheme://user:password@host` URI a user pasted.
    public var displayString: String {
        Self.redactingPassword(in: connectionString)
    }

    static func redactingPassword(in value: String) -> String {
        redactingKeywordPassword(in: redactingURIPassword(in: value))
    }

    /// Masks the password in a `scheme://user:password@host` URI, if present.
    private static func redactingURIPassword(in value: String) -> String {
        guard let scheme = value.range(of: "://") else { return value }
        let authority = value[scheme.upperBound...]
        guard let at = authority.firstIndex(of: "@") else { return value }
        // The '@' must sit in the authority, not later in the path or query.
        for terminator in ["/", "?", "#"] where (authority.firstIndex(of: Character(terminator)).map { $0 < at } ?? false) {
            return value
        }
        guard let colon = authority[..<at].firstIndex(of: ":") else { return value }
        var result = value
        result.replaceSubrange(value.index(after: colon)..<at, with: "••••")
        return result
    }

    /// Masks the value of a `password=…` keyword, honouring libpq single-quoting.
    private static func redactingKeywordPassword(in value: String) -> String {
        var searchStart = value.startIndex
        while let key = value.range(of: "password=", range: searchStart..<value.endIndex) {
            let atBoundary = key.lowerBound == value.startIndex
                || value[value.index(before: key.lowerBound)].isWhitespace
            if atBoundary {
                var result = value
                result.replaceSubrange(key.upperBound..<passwordValueEnd(in: value, from: key.upperBound), with: "••••")
                return result
            }
            searchStart = key.upperBound
        }
        return value
    }

    /// Where a keyword password value ends: the matching close quote for a quoted
    /// value (backslash escapes respected), otherwise the next whitespace.
    private static func passwordValueEnd(in value: String, from start: String.Index) -> String.Index {
        let end = value.endIndex
        guard start < end else { return start }
        if value[start] == "'" {
            var index = value.index(after: start)
            while index < end {
                if value[index] == "\\", value.index(after: index) < end {
                    index = value.index(index, offsetBy: 2)
                    continue
                }
                if value[index] == "'" { return value.index(after: index) }
                index = value.index(after: index)
            }
            return index
        }
        var index = start
        while index < end, !value[index].isWhitespace { index = value.index(after: index) }
        return index
    }

    /// A readable label derived from a connection string, for when the user saved
    /// one without naming it (or for migrating the old single-connection file).
    /// Prefers the database name, then the host, then a plain fallback.
    public static func defaultName(for connectionString: String) -> String {
        let value = connectionString.trimmingCharacters(in: .whitespaces)

        for scheme in ["postgres://", "postgresql://"] where value.hasPrefix(scheme) {
            var rest = String(value.dropFirst(scheme.count))
            if let query = rest.firstIndex(of: "?") { rest = String(rest[..<query]) }
            if let slash = rest.firstIndex(of: "/") {
                let database = String(rest[rest.index(after: slash)...])
                if !database.isEmpty { return database }
                rest = String(rest[..<slash])
            }
            let hostPart = rest.split(separator: "@").last.map(String.init) ?? rest
            let host = hostPart.split(separator: ":").first.map(String.init) ?? hostPart
            if !host.isEmpty { return host }
        }

        if value.contains("=") {
            if let database = keywordValue("dbname", in: value) { return database }
            if let host = keywordValue("host", in: value) { return host }
        }

        // A bare database name.
        if !value.isEmpty, !value.contains(" ") { return value }
        return "connection"
    }

    /// Pulls `key=value` out of a libpq keyword string. Deliberately simple: it
    /// does not handle single-quoted values, which is fine for a display label.
    private static func keywordValue(_ key: String, in conninfo: String) -> String? {
        for token in conninfo.split(separator: " ") {
            let parts = token.split(separator: "=", maxSplits: 1)
            if parts.count == 2, parts[0] == Substring(key) {
                let value = String(parts[1])
                return value.isEmpty ? nil : value
            }
        }
        return nil
    }
}

/// Pure operations on an ordered list of saved connections. The list is kept
/// most-recently-used first, so the head is the default to reconnect to.
public enum ConnectionList {
    /// Inserts `connection` at the front, replacing any existing entry with the
    /// same name (case-insensitively). Adding a connection and re-selecting one
    /// are the same move: it becomes the new most-recent.
    public static func upsert(_ connection: SavedConnection, into list: [SavedConnection]) -> [SavedConnection] {
        var result = list.filter { !$0.name.matches(connection.name) }
        result.insert(connection, at: 0)
        return result
    }

    /// Moves the named connection to the front without changing its data.
    public static func moveToFront(_ name: String, in list: [SavedConnection]) -> [SavedConnection] {
        guard let index = list.firstIndex(where: { $0.name.matches(name) }) else { return list }
        var result = list
        result.insert(result.remove(at: index), at: 0)
        return result
    }

    public static func removing(_ name: String, from list: [SavedConnection]) -> [SavedConnection] {
        list.filter { !$0.name.matches(name) }
    }

    public static func first(named name: String, in list: [SavedConnection]) -> SavedConnection? {
        list.first { $0.name.matches(name) }
    }
}

private extension String {
    func matches(_ other: String) -> Bool {
        caseInsensitiveCompare(other) == .orderedSame
    }
}
