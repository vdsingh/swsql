import Foundation

/// Turns command line arguments into a libpq connection string.
///
/// swsql deliberately does not reimplement Postgres connection resolution. It
/// builds a conninfo string and hands it to libpq, which then applies the same
/// rules `psql` does: PG* environment variables, `~/.pgpass`, service files,
/// SSL modes and all.
public struct ConnectionTarget: Equatable {
    /// The connection string handed to `PQconnectdb`. May be empty, which tells
    /// libpq to rely entirely on the environment and its defaults.
    public var connectionString: String

    public init(connectionString: String) {
        self.connectionString = connectionString
    }

    public enum ParseError: Error, Equatable, CustomStringConvertible {
        case missingValue(String)
        case unknownOption(String)
        case tooManyArguments

        public var description: String {
            switch self {
            case .missingValue(let flag): return "option \(flag) needs a value"
            case .unknownOption(let flag): return "unknown option \(flag)"
            case .tooManyArguments: return "expected at most one connection string or database name"
            }
        }
    }

    public enum Invocation: Equatable {
        case connect(ConnectionTarget)
        /// No connection details were given on the command line, so libpq's own
        /// environment and defaults would apply. Distinct from `.connect` so a
        /// caller can instead reuse a saved connection or prompt for one; the
        /// associated target (application_name only) is the environment-defaults
        /// fallback for callers that want the psql-style behaviour anyway.
        case connectUsingDefaults(ConnectionTarget)
        case help
        case version
    }

    /// Parses arguments in the psql-compatible style.
    ///
    ///     swsql                                  # environment defaults
    ///     swsql mydb                             # a database name
    ///     swsql postgres://user@host:5432/mydb   # a URI
    ///     swsql -h db.internal -U alice -d shop  # discrete options
    public static func parse(arguments: [String]) throws -> Invocation {
        var host: String?
        var port: String?
        var user: String?
        var database: String?
        var positional: [String] = []

        var index = 0
        while index < arguments.count {
            let argument = arguments[index]

            func takeValue(_ flag: String) throws -> String {
                // Support both "-h value" and "-hvalue" / "--host=value".
                if let equals = argument.firstIndex(of: "="), argument.hasPrefix("--") {
                    return String(argument[argument.index(after: equals)...])
                }
                if argument.hasPrefix("-"), !argument.hasPrefix("--"), argument.count > 2 {
                    return String(argument.dropFirst(2))
                }
                index += 1
                guard index < arguments.count else { throw ParseError.missingValue(flag) }
                return arguments[index]
            }

            switch true {
            case argument == "--help" || argument == "-?":
                return .help
            case argument == "--version" || argument == "-V":
                return .version
            case argument == "-h" || argument.hasPrefix("-h") || argument.hasPrefix("--host"):
                host = try takeValue("--host")
            case argument == "-p" || argument.hasPrefix("-p") || argument.hasPrefix("--port"):
                port = try takeValue("--port")
            case argument == "-U" || argument.hasPrefix("-U") || argument.hasPrefix("--username"):
                user = try takeValue("--username")
            case argument == "-d" || argument.hasPrefix("-d") || argument.hasPrefix("--dbname"):
                database = try takeValue("--dbname")
            case argument.hasPrefix("-"):
                throw ParseError.unknownOption(argument)
            default:
                positional.append(argument)
            }
            index += 1
        }

        guard positional.count <= 1 else { throw ParseError.tooManyArguments }

        // A positional argument is either a full connection string or a bare
        // database name, matching psql's behaviour.
        if let positional = positional.first {
            if isConnectionString(positional) {
                return .connect(ConnectionTarget(connectionString: withApplicationName(uriOrKeywords: positional)))
            }
            database = database ?? positional
        }

        let gaveConnectionInfo = host != nil || port != nil || user != nil || database != nil

        var parts: [String] = []
        if let host { parts.append(keyword("host", host)) }
        if let port { parts.append(keyword("port", port)) }
        if let user { parts.append(keyword("user", user)) }
        if let database { parts.append(keyword("dbname", database)) }
        parts.append(keyword("application_name", "swsql"))

        let target = ConnectionTarget(connectionString: parts.joined(separator: " "))
        return gaveConnectionInfo ? .connect(target) : .connectUsingDefaults(target)
    }

    /// A URI, or a keyword string that already contains an `=`.
    static func isConnectionString(_ value: String) -> Bool {
        value.hasPrefix("postgres://")
            || value.hasPrefix("postgresql://")
            || value.contains("=")
    }

    /// Tags the connection so it is identifiable in `pg_stat_activity`, without
    /// clobbering an application name the user set themselves.
    static func withApplicationName(uriOrKeywords value: String) -> String {
        guard !value.contains("application_name") else { return value }

        if value.hasPrefix("postgres://") || value.hasPrefix("postgresql://") {
            return value.contains("?") ? "\(value)&application_name=swsql" : "\(value)?application_name=swsql"
        }
        return "\(value) application_name=swsql"
    }

    /// Formats one `keyword=value` pair, quoting and escaping as libpq requires.
    static func keyword(_ key: String, _ value: String) -> String {
        let needsQuoting = value.isEmpty || value.contains(where: { $0 == " " || $0 == "'" || $0 == "\\" })
        guard needsQuoting else { return "\(key)=\(value)" }
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
        return "\(key)='\(escaped)'"
    }
}
