import Foundation

/// Remembers the connection the user last chose, so swsql can be launched with
/// no arguments and no PG* environment set up at all.
///
/// The saved string can embed a password - a `postgres://` URI carries one, just
/// as libpq service files and `~/.pgpass` do - so it is written `0600` inside a
/// `0700` directory, the same posture psql requires of `~/.pgpass`.
public struct ConnectionStore {
    /// The file holding the saved connection string: one line of text.
    public let fileURL: URL

    /// Points the store at an explicit file. Used by tests.
    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// The default location: `$XDG_CONFIG_HOME/swsql/connection`, falling back to
    /// `~/.config/swsql/connection`.
    public init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        let base: URL
        if let xdg = environment["XDG_CONFIG_HOME"], !xdg.isEmpty {
            base = URL(fileURLWithPath: xdg, isDirectory: true)
        } else {
            let home = environment["HOME"].map { URL(fileURLWithPath: $0, isDirectory: true) }
                ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            base = home.appendingPathComponent(".config", isDirectory: true)
        }
        self.fileURL = base
            .appendingPathComponent("swsql", isDirectory: true)
            .appendingPathComponent("connection", isDirectory: false)
    }

    /// The saved connection string, or nil if nothing legible has been saved.
    public func load() -> String? {
        guard
            let data = try? Data(contentsOf: fileURL),
            let text = String(data: data, encoding: .utf8)
        else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Persists `connectionString`, creating the directory if needed and keeping
    /// the file readable only by its owner.
    public func save(_ connectionString: String) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try Data((connectionString + "\n").utf8).write(to: fileURL, options: .atomic)
        // The atomic write replaces the file, so the mode is set afterwards.
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: fileURL.path
        )
    }

    /// Forgets the saved connection, if there is one. A missing file is not an error.
    public func clear() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }
}
