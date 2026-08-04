import XCTest
@testable import SWSQLCore

final class SavedConnectionTests: XCTestCase {
    // MARK: - defaultName

    func testDefaultNameFromURIPath() {
        XCTAssertEqual(SavedConnection.defaultName(for: "postgres://alice@db.internal/shop"), "shop")
        XCTAssertEqual(SavedConnection.defaultName(for: "postgresql://db/shop?sslmode=require"), "shop")
    }

    func testDefaultNameFromURIHostWhenNoDatabase() {
        XCTAssertEqual(SavedConnection.defaultName(for: "postgres://alice@prod-db:5432/"), "prod-db")
        XCTAssertEqual(SavedConnection.defaultName(for: "postgres://prod-db"), "prod-db")
    }

    func testDefaultNameFromKeywordString() {
        XCTAssertEqual(SavedConnection.defaultName(for: "host=/tmp dbname=shop"), "shop")
        XCTAssertEqual(SavedConnection.defaultName(for: "host=db user=alice"), "db")
    }

    func testDefaultNameFromBareDatabase() {
        XCTAssertEqual(SavedConnection.defaultName(for: "shop"), "shop")
    }

    func testDefaultNameFallsBack() {
        XCTAssertEqual(SavedConnection.defaultName(for: ""), "connection")
    }

    // MARK: - displayString (password redaction for the switcher list)

    private func redacted(_ connectionString: String) -> String {
        SavedConnection(name: "c", connectionString: connectionString).displayString
    }

    func testDisplayStringMasksAKeywordPassword() {
        XCTAssertEqual(redacted("host=db password=secret dbname=shop"), "host=db password=•••• dbname=shop")
        XCTAssertEqual(redacted("password=secret"), "password=••••")
    }

    func testDisplayStringMasksAQuotedKeywordPassword() {
        XCTAssertEqual(redacted("host=db password='se cret' dbname=shop"), "host=db password=•••• dbname=shop")
        XCTAssertEqual(redacted("password='a\\'b' dbname=shop"), "password=•••• dbname=shop")
    }

    func testDisplayStringMasksAURIPassword() {
        XCTAssertEqual(redacted("postgres://alice:secret@db.internal/shop"), "postgres://alice:••••@db.internal/shop")
    }

    func testDisplayStringLeavesConnectionsWithoutAPasswordUntouched() {
        XCTAssertEqual(redacted("host=db user=alice dbname=shop"), "host=db user=alice dbname=shop")
        XCTAssertEqual(redacted("postgres://alice@db.internal/shop"), "postgres://alice@db.internal/shop")
    }

    func testDisplayStringDoesNotMistakeASimilarKeywordForThePassword() {
        // A ':' in the path, and an sslpassword key, must not be treated as the password.
        XCTAssertEqual(redacted("postgres://db.internal/shop?options=-c%20a:b"), "postgres://db.internal/shop?options=-c%20a:b")
        XCTAssertEqual(redacted("host=db sslpassword=x dbname=shop"), "host=db sslpassword=x dbname=shop")
    }

    // MARK: - ConnectionList

    private let staging = SavedConnection(name: "staging", connectionString: "postgres://db/stg")
    private let prod = SavedConnection(name: "prod", connectionString: "postgres://db/prod", isProduction: true)

    func testUpsertInsertsAtFront() {
        let list = ConnectionList.upsert(prod, into: [staging])
        XCTAssertEqual(list.map(\.name), ["prod", "staging"])
    }

    func testUpsertReplacesByNameCaseInsensitively() {
        let renamed = SavedConnection(name: "PROD", connectionString: "postgres://db/prod2", isProduction: true)
        let list = ConnectionList.upsert(renamed, into: [staging, prod])
        XCTAssertEqual(list.map(\.name), ["PROD", "staging"])
        XCTAssertEqual(list.first?.connectionString, "postgres://db/prod2")
        XCTAssertEqual(list.filter { $0.name.lowercased() == "prod" }.count, 1)
    }

    func testMoveToFront() {
        let list = ConnectionList.moveToFront("staging", in: [prod, staging])
        XCTAssertEqual(list.map(\.name), ["staging", "prod"])
    }

    func testMoveToFrontOfMissingIsANoOp() {
        let list = ConnectionList.moveToFront("nope", in: [prod, staging])
        XCTAssertEqual(list.map(\.name), ["prod", "staging"])
    }

    func testRemoving() {
        XCTAssertEqual(ConnectionList.removing("prod", from: [prod, staging]).map(\.name), ["staging"])
    }

    func testFirstNamed() {
        XCTAssertEqual(ConnectionList.first(named: "PROD", in: [staging, prod])?.name, "prod")
        XCTAssertNil(ConnectionList.first(named: "dev", in: [staging, prod]))
    }
}
