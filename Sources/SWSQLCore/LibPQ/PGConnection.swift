import CLibPQ
import Foundation

/// A thin, blocking wrapper around a single libpq connection.
///
/// Every method blocks, so instances must be confined to one thread. `DatabaseService`
/// owns that confinement; nothing else should touch a `PGConnection` directly.
/// The one exception is ``cancelRunningQuery()``, which libpq explicitly documents
/// as safe to call from another thread while a query is in flight.
public final class PGConnection: @unchecked Sendable {
    private let conn: OpaquePointer

    /// Guards `cancelHandle` only. Held for the duration of a `PQcancel` call so the
    /// handle cannot be freed by `close()` while another thread is using it.
    private let cancelLock = NSLock()
    private var cancelHandle: OpaquePointer?
    private var isClosed = false

    /// Notices collected by the libpq callback during the current `exec`.
    private var pendingNotices: [String] = []

    /// OIDs resolved from `pg_type`, so unknown types are looked up once per connection.
    private var typeNameCache: [UInt32: String] = [:]

    /// swsql never materialises an unbounded result set: a `SELECT` against a
    /// billion row table should not take the client down with it.
    public static let defaultRowCap = 10_000

    public var rowCap: Int = PGConnection.defaultRowCap

    // MARK: - Lifecycle

    /// Opens a connection using a libpq connection string or URI.
    ///
    /// An empty string is valid and means "use the PG* environment variables and
    /// the usual defaults", exactly as `psql` does.
    public init(connectionString: String) throws {
        guard let conn = PQconnectdb(connectionString) else {
            throw PostgresError(kind: .client, message: "libpq could not allocate a connection")
        }
        guard PQstatus(conn) == CONNECTION_OK else {
            let message = PGConnection.string(PQerrorMessage(conn))?.trimmedMessage ?? "could not connect"
            PQfinish(conn)
            throw PostgresError(kind: .connection, message: message)
        }
        self.conn = conn
        self.cancelHandle = PQgetCancel(conn)
        installNoticeHandler()
    }

    deinit {
        close()
    }

    /// Idempotent: `close()` is called explicitly by the owner and again from
    /// `deinit`, and libpq would crash on a second `PQfinish`.
    public func close() {
        cancelLock.lock()
        let alreadyClosed = isClosed
        if !alreadyClosed {
            isClosed = true
            if let handle = cancelHandle {
                PQfreeCancel(handle)
                cancelHandle = nil
            }
        }
        cancelLock.unlock()
        guard !alreadyClosed else { return }
        PQfinish(conn)
    }

    // MARK: - Connection metadata

    public var databaseName: String { PGConnection.string(PQdb(conn)) ?? "" }
    public var userName: String { PGConnection.string(PQuser(conn)) ?? "" }
    public var port: String { PGConnection.string(PQport(conn)) ?? "" }

    /// The host libpq actually connected to. For a Unix socket connection `PQhost`
    /// returns the socket directory, which we surface as `local` for readability.
    public var host: String {
        guard let host = PGConnection.string(PQhost(conn)), !host.isEmpty else { return "local" }
        return host.hasPrefix("/") ? "local" : host
    }

    public var serverVersion: String {
        PGConnection.string(PQparameterStatus(conn, "server_version")) ?? "unknown"
    }

    public var isConnected: Bool { PQstatus(conn) == CONNECTION_OK }

    /// Describes the connection the way a status bar should show it.
    public var descriptionForDisplay: String {
        "\(userName)@\(host):\(port)/\(databaseName)"
    }

    // MARK: - Query execution

    /// Runs one or more statements and returns the result of the last one that
    /// produced output, mirroring how `psql` reports a multi-statement send.
    public func execute(_ sql: String) throws -> QueryResult {
        pendingNotices = []
        let start = DispatchTime.now()

        guard let raw = PQexec(conn, sql) else {
            // A null result means libpq failed locally, usually out of memory, or the
            // connection died. Distinguish the two so the UI can offer to reconnect.
            let message = PGConnection.string(PQerrorMessage(conn)) ?? "the command could not be sent"
            throw PostgresError(kind: isConnected ? .client : .connection, message: message.trimmedMessage)
        }
        defer { PQclear(raw) }

        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000_000

        switch PQresultStatus(raw) {
        case PGRES_TUPLES_OK, PGRES_SINGLE_TUPLE:
            var result = try readRows(from: raw)
            result.commandTag = PGConnection.string(PQcmdStatus(raw)) ?? ""
            result.notices = pendingNotices
            result.elapsed = elapsed
            return result

        case PGRES_COMMAND_OK:
            let tag = PGConnection.string(PQcmdStatus(raw)) ?? ""
            let affected = PGConnection.string(PQcmdTuples(raw)).flatMap(Int.init)
            return QueryResult(
                commandTag: tag,
                affectedRows: affected,
                notices: pendingNotices,
                elapsed: elapsed
            )

        case PGRES_EMPTY_QUERY:
            return QueryResult(commandTag: "empty query", notices: pendingNotices, elapsed: elapsed)

        default:
            throw error(from: raw)
        }
    }

    /// Interrupts the statement currently running on this connection.
    ///
    /// Safe to call from a different thread than the one blocked in `execute`.
    /// Returns an error string if libpq could not deliver the cancel request.
    @discardableResult
    public func cancelRunningQuery() -> String? {
        cancelLock.lock()
        defer { cancelLock.unlock() }
        guard let handle = cancelHandle else { return "no connection to cancel" }

        var buffer = [CChar](repeating: 0, count: 256)
        let ok = PQcancel(handle, &buffer, Int32(buffer.count))
        if ok == 1 { return nil }
        return String(cString: buffer)
    }

    // MARK: - Reading results

    private func readRows(from raw: OpaquePointer) throws -> QueryResult {
        let columnCount = Int(PQnfields(raw))
        let serverRowCount = Int(PQntuples(raw))
        let rowCount = min(serverRowCount, rowCap)

        var oids: [UInt32] = []
        oids.reserveCapacity(columnCount)
        for index in 0..<columnCount {
            oids.append(UInt32(PQftype(raw, Int32(index))))
        }
        let typeNames = resolveTypeNames(for: oids)

        var columns: [ResultColumn] = []
        columns.reserveCapacity(columnCount)
        for index in 0..<columnCount {
            let name = PGConnection.string(PQfname(raw, Int32(index))) ?? "?column?"
            let oid = oids[index]
            columns.append(
                ResultColumn(name: name, typeOID: oid, typeName: typeNames[oid] ?? "oid \(oid)")
            )
        }

        var rows: [[String?]] = []
        rows.reserveCapacity(rowCount)
        for rowIndex in 0..<rowCount {
            var row: [String?] = []
            row.reserveCapacity(columnCount)
            for columnIndex in 0..<columnCount {
                if PQgetisnull(raw, Int32(rowIndex), Int32(columnIndex)) == 1 {
                    row.append(nil)
                } else {
                    // Results arrive in text format, so every type - including ones
                    // swsql has never heard of - already has a server rendered value.
                    row.append(PGConnection.string(PQgetvalue(raw, Int32(rowIndex), Int32(columnIndex))) ?? "")
                }
            }
            rows.append(row)
        }

        return QueryResult(columns: columns, rows: rows, truncated: serverRowCount > rowCount)
    }

    /// Fills in type names for OIDs that are not built in, using one catalog query
    /// per set of previously unseen OIDs.
    private func resolveTypeNames(for oids: [UInt32]) -> [UInt32: String] {
        var resolved: [UInt32: String] = [:]
        var unknown: Set<UInt32> = []

        for oid in oids {
            if let builtIn = PGType.name(for: oid) {
                resolved[oid] = builtIn
            } else if let cached = typeNameCache[oid] {
                resolved[oid] = cached
            } else {
                unknown.insert(oid)
            }
        }

        guard !unknown.isEmpty else { return resolved }

        let list = unknown.map(String.init).joined(separator: ",")
        // A failure here is cosmetic: the column header falls back to "oid N".
        guard let raw = PQexec(conn, "SELECT oid, typname FROM pg_type WHERE oid IN (\(list))") else {
            return resolved
        }
        defer { PQclear(raw) }
        guard PQresultStatus(raw) == PGRES_TUPLES_OK else { return resolved }

        for rowIndex in 0..<Int(PQntuples(raw)) {
            guard
                let oidText = PGConnection.string(PQgetvalue(raw, Int32(rowIndex), 0)),
                let oid = UInt32(oidText),
                let name = PGConnection.string(PQgetvalue(raw, Int32(rowIndex), 1))
            else { continue }
            typeNameCache[oid] = name
            resolved[oid] = name
        }
        return resolved
    }

    private func error(from raw: OpaquePointer) -> PostgresError {
        func field(_ code: Character) -> String? {
            PGConnection.string(PQresultErrorField(raw, Int32(code.asciiValue ?? 0)))
        }

        let message = field("M")
            ?? PGConnection.string(PQresultErrorMessage(raw))?.trimmedMessage
            ?? "the server rejected the statement"

        return PostgresError(
            kind: isConnected ? .server : .connection,
            severity: field("S"),
            sqlState: field("C"),
            message: message,
            detail: field("D"),
            hint: field("H"),
            position: field("P").flatMap(Int.init)
        )
    }

    // MARK: - Notices

    /// Routes libpq NOTICE/WARNING output into `pendingNotices` instead of stderr,
    /// which would otherwise scribble over the rendered terminal UI.
    private func installNoticeHandler() {
        let box = Unmanaged.passUnretained(self).toOpaque()
        PQsetNoticeProcessor(conn, { context, message in
            guard let context, let message else { return }
            let connection = Unmanaged<PGConnection>.fromOpaque(context).takeUnretainedValue()
            connection.pendingNotices.append(String(cString: message).trimmedMessage)
        }, box)
    }

    // MARK: - Helpers

    private static func string(_ pointer: UnsafePointer<CChar>?) -> String? {
        guard let pointer else { return nil }
        return String(cString: pointer)
    }

    /// Quotes an identifier using libpq's own escaping, so table and column names
    /// containing quotes, spaces or non-ASCII characters are handled correctly.
    public func quoteIdentifier(_ identifier: String) -> String {
        guard let escaped = PQescapeIdentifier(conn, identifier, strlen(identifier)) else {
            // Fall back to the standard doubling rule.
            return "\"\(identifier.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        defer { PQfreemem(escaped) }
        return String(cString: escaped)
    }

    /// Quotes a string literal using libpq's own escaping.
    public func quoteLiteral(_ literal: String) -> String {
        guard let escaped = PQescapeLiteral(conn, literal, strlen(literal)) else {
            return "'\(literal.replacingOccurrences(of: "'", with: "''"))'"
        }
        defer { PQfreemem(escaped) }
        return String(cString: escaped)
    }
}

private extension String {
    /// libpq messages arrive with a trailing newline and sometimes an "ERROR:  " prefix.
    var trimmedMessage: String {
        var text = trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["ERROR:  ", "FATAL:  ", "NOTICE:  ", "WARNING:  "] where text.hasPrefix(prefix) {
            text.removeFirst(prefix.count)
            break
        }
        return text
    }
}
