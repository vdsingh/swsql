import Foundation
import SWSQLCore
import SwiftTUI

let version = "0.1.0"

let usage = """
swsql \(version) - a PostgreSQL client for the terminal

USAGE
  swsql [connection] [options]

CONNECTION
  swsql                              use the PG* environment variables
  swsql mydb                         connect to a database by name
  swsql postgres://user@host/mydb    connect with a URI
  swsql "host=db user=alice"         connect with a libpq keyword string

OPTIONS
  -h, --host <host>       server host or socket directory
  -p, --port <port>       server port
  -U, --username <name>   user to connect as
  -d, --dbname <name>     database to connect to
  -?, --help              show this message
  -V, --version           show the version

Connection details not given here are resolved by libpq exactly as psql
resolves them, including PGPASSWORD, ~/.pgpass, service files and sslmode.
"""

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("swsql: \(message)\n".utf8))
    exit(2)
}

let invocation: ConnectionTarget.Invocation
do {
    invocation = try ConnectionTarget.parse(arguments: Array(CommandLine.arguments.dropFirst()))
} catch let error as ConnectionTarget.ParseError {
    fail("\(error.description)\n\nRun swsql --help for usage.")
} catch {
    fail("\(error)")
}

/// Reads a saved connection string back into a target, or nil if the file is
/// absent or no longer parses.
func savedTarget(_ input: String) -> ConnectionTarget? {
    guard let invocation = try? ConnectionTarget.parse(arguments: [input]) else { return nil }
    switch invocation {
    case .connect(let target), .connectUsingDefaults(let target): return target
    case .help, .version: return nil
    }
}

/// Builds the model, connects if there is somewhere to connect, and runs the UI.
func launch(target: ConnectionTarget?, environmentDefaults: ConnectionTarget, store: ConnectionStore) {
    let model = AppModel(
        database: DatabaseService(),
        store: store,
        target: target,
        environmentDefaults: environmentDefaults
    )

    // Connecting is dispatched now, but its completion cannot land until the main
    // queue starts running, which happens inside Application.start(). With no
    // target the app opens on its setup screen and asks for a URL instead.
    if target != nil { model.start() }

    Application(rootView: RootView(model: model)).start()
}

let store = ConnectionStore()

switch invocation {
case .help:
    print(usage)
    exit(0)
case .version:
    print("swsql \(version)")
    exit(0)
case .connect(let target):
    // A connection was named on the command line: use it as-is, ephemerally.
    launch(target: target, environmentDefaults: target, store: store)
case .connectUsingDefaults(let environmentDefaults):
    // Nothing was named. Reuse the URL saved from a previous run if there is one;
    // otherwise open on the setup screen and ask for one.
    let target = store.load().flatMap(savedTarget)
    launch(target: target, environmentDefaults: environmentDefaults, store: store)
}
