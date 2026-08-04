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

#if canImport(Darwin)
/// What the terminal's delayed-suspend character was before swsql disabled it,
/// so the atexit handler can put it back for the shell.
var originalDelayedSuspend: UInt8 = 0x19

/// BSD terminals reserve ⌃Y as the "delayed suspend" character: with ISIG on,
/// reading it stops the process instead of delivering the byte - and the input
/// loop's pending read then dies on an empty non-blocking file descriptor. ⌃Y
/// is swsql's copy key, so hand the byte back to the application. Must run
/// before `Application.start()`, whose raw-mode setup leaves `c_cc` alone.
func claimCtrlYFromTheTerminal() {
    var attributes = termios()
    guard tcgetattr(STDIN_FILENO, &attributes) == 0 else { return }
    withUnsafeMutableBytes(of: &attributes.c_cc) { characters in
        originalDelayedSuspend = characters[Int(VDSUSP)]
        characters[Int(VDSUSP)] = 0xff // _POSIX_VDISABLE
    }
    guard tcsetattr(STDIN_FILENO, TCSANOW, &attributes) == 0 else { return }
    atexit {
        var attributes = termios()
        guard tcgetattr(STDIN_FILENO, &attributes) == 0 else { return }
        withUnsafeMutableBytes(of: &attributes.c_cc) { characters in
            characters[Int(VDSUSP)] = originalDelayedSuspend
        }
        tcsetattr(STDIN_FILENO, TCSANOW, &attributes)
    }
}
#else
/// Linux has no delayed-suspend character, so ⌃Y already arrives as input.
func claimCtrlYFromTheTerminal() {}
#endif

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
        // While the switcher waits to confirm a removal, y/⏎ confirms and n keeps
        // it. Ordinary text is swallowed so a stray letter can't fall through to
        // switching or the editor, but control keys (^C/^D to quit) still pass.
        // Arrow keys arrive as escape sequences that never reach this handler, so
        // navigating away cancels the removal on its own via focusConnection.
        if model.isConfirmingRemoval {
            switch character {
            case "y", "Y", "\n", "\r":
                model.confirmRemoval()
                return true
            case "n", "N":
                model.cancelRemoval()
                return true
            case "\u{1b}": // Escape: cancel
                model.handleEscape()
                return true
            default:
                return character >= " "
            }
        }

        switch character {
        case "\u{12}": // Ctrl-R (also a Cmd-R / Cmd-Enter remap): run
            model.runCurrentQuery()
            return true
        case "\u{06}": // Ctrl-F (also a Cmd-F remap): format
            model.formatQuery()
            return true
        case "\u{19}": // Ctrl-Y (also a Cmd-C remap): copy the highlighted cell
            model.copySelectedCell()
            return true
        case "\u{1b}": // Escape: close the completion menu, or go back to the grid
            model.handleEscape()
            return true
        case "d", "D":
            // Remove the highlighted connection - but only in the switcher, so d
            // stays an ordinary character everywhere else (the editor).
            guard model.pane == .connections else { return false }
            model.requestRemoveFocusedConnection()
            return true
        default:
            return false
        }
    }
    claimCtrlYFromTheTerminal()
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
