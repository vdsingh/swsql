import Foundation

/// Owns the libpq connection and the one thread allowed to touch it.
///
/// libpq is blocking and not thread safe, while the TUI runs on the main queue and
/// must never stall. Everything therefore goes through a serial background queue,
/// with results delivered back on the main queue. The single exception is
/// ``cancelRunningQuery()``, which libpq documents as callable from another thread.
public final class DatabaseService: @unchecked Sendable {
    private let queue = DispatchQueue(label: "llc.w00w00.swsql.database", qos: .userInitiated)

    /// Only touched on `queue`.
    private var connection: PGConnection?

    /// A second reference to the same connection, published under a lock purely so
    /// the main thread can issue a cancel while `queue` is blocked inside `PQexec`.
    private let cancelLock = NSLock()
    private var cancelTarget: PGConnection?

    public init() {}

    /// Details about an established connection, safe to read on the main queue.
    public struct ConnectionInfo: Equatable {
        public var display: String
        public var database: String
        public var serverVersion: String
    }

    // MARK: - Lifecycle

    public func connect(
        to target: ConnectionTarget,
        completion: @escaping (Result<ConnectionInfo, PostgresError>) -> Void
    ) {
        queue.async {
            self.teardownConnection()
            do {
                let connection = try PGConnection(connectionString: target.connectionString)
                self.connection = connection
                self.cancelLock.lock()
                self.cancelTarget = connection
                self.cancelLock.unlock()

                let info = ConnectionInfo(
                    display: connection.descriptionForDisplay,
                    database: connection.databaseName,
                    serverVersion: connection.serverVersion
                )
                DispatchQueue.main.async { completion(.success(info)) }
            } catch let error as PostgresError {
                DispatchQueue.main.async { completion(.failure(error)) }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(PostgresError(kind: .connection, message: "\(error)")))
                }
            }
        }
    }

    public func disconnect() {
        queue.async { self.teardownConnection() }
    }

    private func teardownConnection() {
        cancelLock.lock()
        cancelTarget = nil
        cancelLock.unlock()
        connection?.close()
        connection = nil
    }

    // MARK: - Work

    /// Runs `work` on the database queue with the live connection, then delivers
    /// the outcome on the main queue.
    public func perform<T>(
        _ work: @escaping (PGConnection) throws -> T,
        completion: @escaping (Result<T, PostgresError>) -> Void
    ) {
        queue.async {
            guard let connection = self.connection else {
                DispatchQueue.main.async {
                    completion(.failure(PostgresError(kind: .connection, message: "not connected")))
                }
                return
            }
            do {
                let value = try work(connection)
                DispatchQueue.main.async { completion(.success(value)) }
            } catch let error as PostgresError {
                DispatchQueue.main.async { completion(.failure(error)) }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(PostgresError(kind: .client, message: "\(error)")))
                }
            }
        }
    }

    /// Convenience wrapper for a plain statement.
    public func execute(
        _ sql: String,
        completion: @escaping (Result<QueryResult, PostgresError>) -> Void
    ) {
        perform({ try $0.execute(sql) }, completion: completion)
    }

    /// Asks the server to abort whatever statement is currently running.
    /// Returns an error description when the request itself could not be sent.
    @discardableResult
    public func cancelRunningQuery() -> String? {
        cancelLock.lock()
        let target = cancelTarget
        cancelLock.unlock()
        guard let target else { return "not connected" }
        return target.cancelRunningQuery()
    }
}
