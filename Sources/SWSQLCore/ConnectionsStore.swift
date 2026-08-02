import Foundation

/// Resolves swsql's config directory the same way for every store:
/// `$XDG_CONFIG_HOME/swsql`, falling back to `~/.config/swsql`.
public enum ConfigDirectory {
    public static func url(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        let base: URL
        if let xdg = environment["XDG_CONFIG_HOME"], !xdg.isEmpty {
            base = URL(fileURLWithPath: xdg, isDirectory: true)
        } else {
            let home = environment["HOME"].map { URL(fileURLWithPath: $0, isDirectory: true) }
                ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            base = home.appendingPathComponent(".config", isDirectory: true)
        }
        return base.appendingPathComponent("swsql", isDirectory: true)
    }
}

/// Stores the user's named connections as a JSON list, most-recently-used first.
///
/// Like the single-connection file it supersedes, an entry can embed a password,
/// so the file is written `0600` under a `0700` directory. On first read it
/// migrates the old single `connection` file into a one-element list, so nobody
/// loses the connection they had saved.
public struct ConnectionsStore {
    /// The file holding the connections, as a JSON array.
    public let fileURL: URL

    /// The old single-connection file, read once to migrate it.
    private let legacy: ConnectionStore

    public init(directory: URL) {
        self.fileURL = directory.appendingPathComponent("connections.json", isDirectory: false)
        self.legacy = ConnectionStore(fileURL: directory.appendingPathComponent("connection", isDirectory: false))
    }

    public init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.init(directory: ConfigDirectory.url(environment: environment))
    }

    /// The saved connections. Empty on a fresh install.
    public func load() -> [SavedConnection] {
        if let data = try? Data(contentsOf: fileURL),
           let connections = try? JSONDecoder().decode([SavedConnection].self, from: data) {
            return connections
        }
        // Migrate the pre-multi-connection file, if one is there.
        if let string = legacy.load() {
            let migrated = [SavedConnection(name: SavedConnection.defaultName(for: string), connectionString: string)]
            try? save(migrated)
            return migrated
        }
        return []
    }

    /// Persists the list, creating the directory if needed and keeping the file
    /// readable only by its owner.
    public func save(_ connections: [SavedConnection]) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(connections).write(to: fileURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }
}
