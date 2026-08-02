import Foundation

/// A structured error coming back from the server or from libpq itself.
///
/// Postgres reports far more than a message string: a SQLSTATE code, an optional
/// detail and hint, and often the character offset in the statement that caused
/// the problem. Keeping those separate lets the UI show a genuinely useful error
/// pane instead of one undifferentiated blob of text.
public struct PostgresError: Error, Equatable {
    public enum Kind: Equatable {
        /// The connection could not be established, or was lost.
        case connection
        /// The server rejected the statement.
        case server
        /// libpq ran out of memory or otherwise failed locally.
        case client
    }

    public var kind: Kind
    public var severity: String?
    /// Five character SQLSTATE, e.g. `42P01` for "undefined table".
    public var sqlState: String?
    public var message: String
    public var detail: String?
    public var hint: String?
    /// 1-based character offset into the statement, when the server reports one.
    public var position: Int?

    public init(
        kind: Kind,
        severity: String? = nil,
        sqlState: String? = nil,
        message: String,
        detail: String? = nil,
        hint: String? = nil,
        position: Int? = nil
    ) {
        self.kind = kind
        self.severity = severity
        self.sqlState = sqlState
        self.message = message
        self.detail = detail
        self.hint = hint
        self.position = position
    }

    /// A single line suitable for the status bar.
    public var summary: String {
        let firstLine = message.split(separator: "\n").first.map(String.init) ?? message
        if let sqlState {
            return "\(sqlState): \(firstLine)"
        }
        return firstLine
    }

    /// Every populated field, one per line, for the error pane.
    ///
    /// libpq's own messages are sometimes several lines - the "server closed the
    /// connection unexpectedly" report is three - so embedded newlines become real
    /// lines here rather than being flattened into one unreadable run.
    public var lines: [String] {
        var lines: [String] = []
        let label = severity ?? "ERROR"
        let prefix = sqlState.map { "\(label) [\($0)]  " } ?? "\(label)  "

        for (index, part) in message.split(separator: "\n").enumerated() {
            let text = part.trimmingCharacters(in: .whitespaces)
            lines.append(index == 0 ? prefix + text : String(repeating: " ", count: 2) + text)
        }
        if lines.isEmpty { lines.append(prefix) }

        if let detail { lines.append("DETAIL:  \(detail)") }
        if let hint { lines.append("HINT:    \(hint)") }
        if let position { lines.append("POSITION: character \(position)") }
        return lines
    }
}
