import XCTest
@testable import SWSQLCore

final class ConnectionTargetTests: XCTestCase {
    private func connectionString(_ arguments: [String]) throws -> String {
        switch try ConnectionTarget.parse(arguments: arguments) {
        case .connect(let target), .connectUsingDefaults(let target):
            return target.connectionString
        case .help, .version:
            XCTFail("expected a connection for \(arguments)")
            return ""
        }
    }

    func testNoArgumentsLeavesResolutionToLibpq() throws {
        XCTAssertEqual(try connectionString([]), "application_name=swsql")
    }

    func testNoArgumentsIsReportedAsDefaultsSoASavedURLCanBePreferred() throws {
        guard case .connectUsingDefaults = try ConnectionTarget.parse(arguments: []) else {
            return XCTFail("expected .connectUsingDefaults with no arguments")
        }
    }

    func testAnyGivenConnectionInfoIsReportedAsAnExplicitConnection() throws {
        for arguments in [["shop"], ["postgres://db/shop"], ["-d", "shop"], ["host=db"]] {
            guard case .connect = try ConnectionTarget.parse(arguments: arguments) else {
                return XCTFail("expected .connect for \(arguments)")
            }
        }
    }

    func testBareNameIsTreatedAsADatabase() throws {
        XCTAssertEqual(try connectionString(["shop"]), "dbname=shop application_name=swsql")
    }

    // MARK: - keywordString (the setup screen's individual-fields path)

    func testKeywordStringBuildsFromTheParts() {
        XCTAssertEqual(
            ConnectionTarget.keywordString(host: "db.internal", port: "5432", user: "alice", database: "shop"),
            "host=db.internal port=5432 user=alice dbname=shop"
        )
    }

    func testKeywordStringDropsBlankFieldsSoLibpqDefaultsApply() {
        XCTAssertEqual(ConnectionTarget.keywordString(database: "shop"), "dbname=shop")
        XCTAssertEqual(ConnectionTarget.keywordString(host: "  ", user: "\t"), "")
        XCTAssertEqual(ConnectionTarget.keywordString(), "")
    }

    func testKeywordStringQuotesAndEscapesValues() {
        XCTAssertEqual(
            ConnectionTarget.keywordString(password: "p ass'word"),
            "password='p ass\\'word'"
        )
    }

    func testKeywordStringRoundTripsThroughParseAsAnExplicitConnection() throws {
        let conninfo = ConnectionTarget.keywordString(host: "db", user: "alice", database: "shop")
        guard case .connect(let target) = try ConnectionTarget.parse(arguments: [conninfo]) else {
            return XCTFail("expected an explicit connection")
        }
        // Re-parsing tags it with the application name, exactly like a pasted URL.
        XCTAssertEqual(target.connectionString, "host=db user=alice dbname=shop application_name=swsql")
    }

    func testURIIsPassedThroughWithTheApplicationNameAppended() throws {
        XCTAssertEqual(
            try connectionString(["postgres://alice@db.internal/shop"]),
            "postgres://alice@db.internal/shop?application_name=swsql"
        )
        XCTAssertEqual(
            try connectionString(["postgresql://db/shop?sslmode=require"]),
            "postgresql://db/shop?sslmode=require&application_name=swsql"
        )
    }

    func testAnExplicitApplicationNameIsNotOverridden() throws {
        XCTAssertEqual(
            try connectionString(["postgres://db/shop?application_name=mine"]),
            "postgres://db/shop?application_name=mine"
        )
    }

    func testKeywordStringIsPassedThrough() throws {
        XCTAssertEqual(
            try connectionString(["host=db user=alice"]),
            "host=db user=alice application_name=swsql"
        )
    }

    func testSeparateOptions() throws {
        XCTAssertEqual(
            try connectionString(["-h", "db.internal", "-p", "6432", "-U", "alice", "-d", "shop"]),
            "host=db.internal port=6432 user=alice dbname=shop application_name=swsql"
        )
    }

    func testAttachedAndLongFormOptions() throws {
        XCTAssertEqual(
            try connectionString(["-hdb.internal", "--port=6432", "--username", "alice"]),
            "host=db.internal port=6432 user=alice application_name=swsql"
        )
    }

    func testValuesNeedingQuotesAreEscaped() throws {
        XCTAssertEqual(
            try connectionString(["-U", "a person's name"]),
            #"user='a person\'s name' application_name=swsql"#
        )
    }

    func testHelpAndVersion() throws {
        XCTAssertEqual(try ConnectionTarget.parse(arguments: ["--help"]), .help)
        XCTAssertEqual(try ConnectionTarget.parse(arguments: ["-?"]), .help)
        XCTAssertEqual(try ConnectionTarget.parse(arguments: ["--version"]), .version)
        XCTAssertEqual(try ConnectionTarget.parse(arguments: ["-V"]), .version)
    }

    func testUnknownOptionIsRejected() {
        XCTAssertThrowsError(try ConnectionTarget.parse(arguments: ["--nope"])) { error in
            XCTAssertEqual(error as? ConnectionTarget.ParseError, .unknownOption("--nope"))
        }
    }

    func testMissingValueIsRejected() {
        XCTAssertThrowsError(try ConnectionTarget.parse(arguments: ["-h"])) { error in
            XCTAssertEqual(error as? ConnectionTarget.ParseError, .missingValue("--host"))
        }
    }

    func testTooManyPositionalArgumentsAreRejected() {
        XCTAssertThrowsError(try ConnectionTarget.parse(arguments: ["one", "two"])) { error in
            XCTAssertEqual(error as? ConnectionTarget.ParseError, .tooManyArguments)
        }
    }
}
