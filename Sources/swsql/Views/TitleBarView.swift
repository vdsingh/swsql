import SWSQLCore
import SwiftTUI

/// The inverted bar across the top: who we are connected to, and what the
/// connection is doing right now.
struct TitleBarView: View {
    @ObservedObject var model: AppModel
    let width: Int

    var body: some View {
        // Connected to a production-tagged database, the whole bar turns into a
        // warning banner so the environment can never be mistaken. Clicking the
        // bar opens the connection selector; `.onClick` keeps it out of keyboard
        // focus, so the prompt still takes the initial focus and typed input.
        Text(line)
            .background(model.isConnectedToProduction ? Theme.failure : Theme.headerBackground)
            .foregroundColor(Theme.headerForeground)
            .bold()
            .onClick { model.toggleConnections() }
    }

    private var line: String {
        let right = "\(indicator) "
        // The connection state is the part worth keeping when space runs out, so
        // the description on the left is what gets truncated.
        let leftBudget = max(1, width - right.count - 1)
        let left = DisplayText.truncate(" swsql  \(label)\(target)\(chevron)", to: leftBudget)

        let gap = max(1, width - left.count - right.count)
        return DisplayText.truncate(left + String(repeating: " ", count: gap) + right, to: width)
    }

    /// A hint that the connection is a selector, shown once there is something to
    /// select (not on the setup screen).
    private var chevron: String {
        model.connectionState == .unconfigured ? "" : "  ▾"
    }

    /// The active connection's name, when it has one, so multiple databases are
    /// told apart at a glance.
    private var label: String {
        guard let name = model.activeConnection?.name else { return "" }
        return "[\(name)]  "
    }

    private var target: String {
        switch model.connectionState {
        case .unconfigured:
            return "not connected"
        case .connecting:
            return "connecting…"
        case .connected(let info):
            return "\(info.display)  ·  PostgreSQL \(info.serverVersion)"
        case .failed:
            return "disconnected"
        }
    }

    private var indicator: String {
        if model.isConnectedToProduction, !model.isRunning { return "⚠ PRODUCTION  ● ready" }
        if model.isRunning { return "◐ running" }
        switch model.connectionState {
        case .unconfigured: return "○ setup"
        case .connecting: return "◌ connecting"
        case .connected: return "● ready"
        case .failed: return "○ disconnected"
        }
    }
}

/// The status line: the outcome of whatever happened last.
struct StatusBarView: View {
    @ObservedObject var model: AppModel
    let width: Int

    var body: some View {
        Text(DisplayText.pad(" " + DisplayText.singleLine(model.status), to: width, alignment: .left))
            .foregroundColor(color)
    }

    private var color: Color {
        switch model.statusKind {
        case .info: return Theme.dim
        case .success: return Theme.success
        case .failure: return Theme.failure
        }
    }
}

/// The bottom hint line, which changes with the visible pane so it always
/// describes keys that actually do something right now.
struct KeyHintsView: View {
    @ObservedObject var model: AppModel
    let width: Int

    var body: some View {
        Text(DisplayText.pad(" " + hints, to: width, alignment: .left))
            .foregroundColor(Theme.dim)
    }

    private var hints: String {
        switch model.pane {
        case .help:
            return "↑↓←→ move   ⏎ activate   Esc back to the grid   ^C quit"
        case .rowDetail:
            return "↑↓←→ move   Esc back to the grid   ^C quit"
        case .history:
            return "↑↓ pick   ⏎ load into the editor   Esc back   ^C quit"
        case .connections:
            return model.isConfirmingRemoval
                ? "y remove   n keep   Esc cancel"
                : "↑↓ pick   ⏎ switch   d remove   [＋ Add] adds one   Esc back   ^C quit"
        case .structure:
            return "↑↓←→ move   Esc back to the grid   ^C quit"
        case .data:
            return "⌃R run   ⏎ newline (editor) / open row   ↑↓←→ move   ^C quit"
        }
    }
}
