import XCTest
@testable import SWSQLCore

final class ConnectionsStoreTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("swsql-connections-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func store() -> ConnectionsStore { ConnectionsStore(directory: directory) }

    func testLoadIsEmptyOnAFreshInstall() {
        XCTAssertEqual(store().load(), [])
    }

    func testSaveAndLoadRoundTripsIncludingProductionFlag() throws {
        let connections = [
            SavedConnection(name: "prod", connectionString: "postgres://db/prod", isProduction: true),
            SavedConnection(name: "staging", connectionString: "postgres://db/stg"),
        ]
        try store().save(connections)
        XCTAssertEqual(store().load(), connections)
    }

    func testTheFileIsReadableOnlyByItsOwner() throws {
        try store().save([SavedConnection(name: "prod", connectionString: "postgres://a:secret@db/prod")])
        let perms = try FileManager.default
            .attributesOfItem(atPath: store().fileURL.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(perms?.int16Value, 0o600)
    }

    func testMigratesTheLegacySingleConnectionFile() throws {
        // Seed the pre-multi-connection file the way ConnectionStore would have.
        let legacy = ConnectionStore(fileURL: directory.appendingPathComponent("connection"))
        try legacy.save("host=/tmp dbname=shop")

        let migrated = store().load()
        XCTAssertEqual(migrated.count, 1)
        XCTAssertEqual(migrated.first?.connectionString, "host=/tmp dbname=shop")
        XCTAssertEqual(migrated.first?.name, "shop") // derived from dbname
        XCTAssertFalse(migrated.first?.isProduction ?? true)

        // Migration is persisted, so a second load reads the new file, not the legacy one.
        XCTAssertTrue(FileManager.default.fileExists(atPath: store().fileURL.path))
        XCTAssertEqual(store().load(), migrated)
    }

    func testTheJSONFileWinsOverTheLegacyFile() throws {
        let legacy = ConnectionStore(fileURL: directory.appendingPathComponent("connection"))
        try legacy.save("postgres://db/old")
        try store().save([SavedConnection(name: "current", connectionString: "postgres://db/new")])

        XCTAssertEqual(store().load().map(\.name), ["current"])
    }
}
