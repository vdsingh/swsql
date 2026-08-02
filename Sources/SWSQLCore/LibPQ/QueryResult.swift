import Foundation

/// One column of a result set.
public struct ResultColumn: Equatable {
    public var name: String
    public var typeOID: UInt32
    public var typeName: String

    public init(name: String, typeOID: UInt32, typeName: String) {
        self.name = name
        self.typeOID = typeOID
        self.typeName = typeName
    }

    /// Numbers read better flushed right; everything else reads better flushed left.
    public var alignment: ColumnAlignment {
        PGType.isNumeric(oid: typeOID) ? .right : .left
    }
}

public enum ColumnAlignment: Equatable {
    case left
    case right
}

/// The outcome of a single statement.
///
/// `rows` holds `nil` for SQL NULL so the UI can distinguish it from the empty
/// string - a distinction that matters often enough to be worth carrying.
public struct QueryResult: Equatable {
    public var columns: [ResultColumn]
    public var rows: [[String?]]
    /// The command tag the server returned, e.g. `SELECT 42` or `UPDATE 3`.
    public var commandTag: String
    /// Rows affected, for statements that report it.
    public var affectedRows: Int?
    /// NOTICE / WARNING messages raised while the statement ran.
    public var notices: [String]
    public var elapsed: TimeInterval
    /// True when the statement was truncated by swsql's own row cap.
    public var truncated: Bool

    public init(
        columns: [ResultColumn] = [],
        rows: [[String?]] = [],
        commandTag: String = "",
        affectedRows: Int? = nil,
        notices: [String] = [],
        elapsed: TimeInterval = 0,
        truncated: Bool = false
    ) {
        self.columns = columns
        self.rows = rows
        self.commandTag = commandTag
        self.affectedRows = affectedRows
        self.notices = notices
        self.elapsed = elapsed
        self.truncated = truncated
    }

    public var returnsRows: Bool { !columns.isEmpty }

    /// A one line description of what happened, for the status bar.
    public var summary: String {
        let millis = String(format: "%.1f ms", elapsed * 1000)
        if returnsRows {
            let noun = rows.count == 1 ? "row" : "rows"
            let count = truncated ? "\(rows.count)+ \(noun) (capped)" : "\(rows.count) \(noun)"
            return "\(count), \(columns.count) \(columns.count == 1 ? "column" : "columns") in \(millis)"
        }
        let tag = commandTag.isEmpty ? "OK" : commandTag
        return "\(tag) in \(millis)"
    }
}
