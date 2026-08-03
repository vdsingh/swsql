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

/// Builds the model with its starting point and runs the UI.
func launch(initial: AppModel.Initial, connections: [SavedConnection], environmentDefaults: ConnectionTarget) {
    let model = AppModel(
        database: DatabaseService(),
        store: ConnectionsStore(),
        connections: connections,
        initial: initial,
        environmentDefaults: environmentDefaults
    )

    // Connecting is dispatched now, but its completion cannot land until the main
    // queue starts running inside Application.start(). With `.setup` there is no
    // target and start() is a no-op, so the app opens on the setup screen.
    model.start()

    let application = Application(rootView: RootView(model: model))
    // Ctrl-R runs the query from anywhere, not only while the editor has focus -
    // this is also what a terminal Cmd-R→^R remap triggers.
    application.keyHandler = { character in
        if character == "\u{12}" {
            model.runCurrentQuery()
            return true
        }
        return false
    }
    application.start()
}

func runApp() {
    let savedConnections = ConnectionsStore().load()
    // Only used by the "empty URL → environment defaults" escape hatch on the
    // setup screen; libpq resolves the rest from PG* and its own defaults.
    let environmentDefaults = ConnectionTarget(connectionString: "application_name=swsql")
    let rawArguments = Array(CommandLine.arguments.dropFirst())

    // `swsql <name>` selects a saved connection by name.
    if rawArguments.count == 1, !rawArguments[0].hasPrefix("-"),
       let match = ConnectionList.first(named: rawArguments[0], in: savedConnections) {
        launch(initial: .saved(match), connections: savedConnections, environmentDefaults: environmentDefaults)
        return
    }

    let invocation: ConnectionTarget.Invocation
    do {
        invocation = try ConnectionTarget.parse(arguments: rawArguments)
    } catch let error as ConnectionTarget.ParseError {
        fail("\(error.description)\n\nRun swsql --help for usage.")
    } catch {
        fail("\(error)")
    }

    switch invocation {
    case .help:
        print(usage)
        exit(0)
    case .version:
        print("swsql \(version)")
        exit(0)
    case .connect(let target):
        // A connection named on the command line: use it as-is, unsaved.
        launch(initial: .ephemeral(target), connections: savedConnections, environmentDefaults: environmentDefaults)
    case .connectUsingDefaults:
        // Nothing named: reconnect to the most recent saved connection, or open
        // the setup screen when there are none.
        if let recent = savedConnections.first {
            launch(initial: .saved(recent), connections: savedConnections, environmentDefaults: environmentDefaults)
        } else {
            launch(initial: .setup, connections: savedConnections, environmentDefaults: environmentDefaults)
        }
    }
}

runApp()
