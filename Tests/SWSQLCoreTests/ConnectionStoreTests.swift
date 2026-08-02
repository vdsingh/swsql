import XCTest
@testable import SWSQLCore

final class ConnectionStoreTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("swsql-store-tests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func store() -> ConnectionStore {
        ConnectionStore(fileURL: directory.appendingPathComponent("connection"))
    }

    func testLoadReturnsNilBeforeAnythingIsSaved() {
        XCTAssertNil(store().load())
    }

    func testASavedStringRoundTrips() throws {
        let store = store()
        try store.save("postgres://alice@db/shop")
        XCTAssertEqual(store.load(), "postgres://alice@db/shop")
    }

    func testSavingCreatesTheDirectoryAndRoundTripsThroughAFreshInstance() throws {
        try store().save("host=db user=alice")
        // A separate instance pointed at the same file must read what was written,
        // which is what a later launch does.
        XCTAssertEqual(store().load(), "host=db user=alice")
    }

    func testSurroundingWhitespaceIsIgnored() throws {
        let file = directory.appendingPathComponent("connection")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("  postgres://db/shop \n".utf8).write(to: file)
        XCTAssertEqual(store().load(), "postgres://db/shop")
    }

    func testAnEmptyFileLoadsAsNil() throws {
        let file = directory.appendingPathComponent("connection")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("\n   \n".utf8).write(to: file)
        XCTAssertNil(store().load())
    }

    func testTheSavedFileIsReadableOnlyByItsOwner() throws {
        let store = store()
        try store.save("postgres://alice:secret@db/shop")
        let permissions = try FileManager.default
            .attributesOfItem(atPath: store.fileURL.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.int16Value, 0o600)
    }

    func testSavingOverwritesAnEarlierValue() throws {
        let store = store()
        try store.save("postgres://db/first")
        try store.save("postgres://db/second")
        XCTAssertEqual(store.load(), "postgres://db/second")
    }

    func testClearForgetsTheSavedConnection() throws {
        let store = store()
        try store.save("postgres://db/shop")
        try store.clear()
        XCTAssertNil(store.load())
    }

    func testClearIsHarmlessWhenNothingWasSaved() {
        XCTAssertNoThrow(try store().clear())
    }

    func testTheDefaultLocationHonoursXDGConfigHome() {
        let store = ConnectionStore(environment: ["XDG_CONFIG_HOME": "/tmp/cfg"])
        XCTAssertEqual(store.fileURL.path, "/tmp/cfg/swsql/connection")
    }

    func testTheDefaultLocationFallsBackToDotConfigUnderHome() {
        let store = ConnectionStore(environment: ["HOME": "/home/alice"])
        XCTAssertEqual(store.fileURL.path, "/home/alice/.config/swsql/connection")
    }
}
