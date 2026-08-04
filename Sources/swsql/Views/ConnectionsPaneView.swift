import SWSQLCore
import SwiftTUI

/// The saved-connection switcher: pick one to connect to it, or add another.
///
/// Production connections are drawn in the warning colour so the one you must be
/// careful with stands out even before you switch to it (the title bar then
/// turns into a full banner). Rows resolve their connection by name at press
/// time, so the list can reorder under them without the actions going stale.
struct ConnectionsPaneView: View {
    @ObservedObject var model: AppModel
    let layout: ScreenLayout

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(DisplayText.pad(" Connections", to: layout.mainWidth, alignment: .left))
                .foregroundColor(Theme.accent)
                .bold()
            ForEach(model.connections.indexed) { entry in
                Button(
                    action: { model.connect(named: entry.value.name) },
                    hover: { model.focusConnection(entry.value.name) },
                    label: {
                        Text(row(for: entry.value))
                            .foregroundColor(color(for: entry.value))
                    }
                )
            }
            Button("  ＋ Add a connection", hover: { model.clearConnectionFocus() }, action: { model.beginAddConnection() })
                .foregroundColor(Theme.accent)
            emptyNotice
            Filler(height: fillerHeight, width: layout.mainWidth)
        }
    }

    /// One connection as a single line: a marker (● active, ✗ pending removal),
    /// the name, its target and a production tag.
    private func row(for connection: SavedConnection) -> String {
        let tag = connection.isProduction ? "  ⚠ PRODUCTION" : ""
        let name = DisplayText.pad(connection.name, to: 18, alignment: .left)
        let detail = DisplayText.singleLine(connection.connectionString)
        let room = max(1, layout.mainWidth - 18 - tag.count - 6)
        return " \(marker(for: connection)) \(name)  \(DisplayText.truncate(detail, to: room))\(tag)"
    }

    private func marker(for connection: SavedConnection) -> String {
        if isPendingRemoval(connection) { return "✗" }
        return isActive(connection) ? "●" : " "
    }

    /// The pending-removal row is drawn in the failure colour so the one about to
    /// be deleted is unmistakable while the y/n prompt is up.
    private func color(for connection: SavedConnection) -> Color {
        if isPendingRemoval(connection) { return Theme.failure }
        return connection.isProduction ? Theme.warning : Theme.text
    }

    private func isActive(_ connection: SavedConnection) -> Bool {
        model.activeConnection?.name.caseInsensitiveCompare(connection.name) == .orderedSame
    }

    private func isPendingRemoval(_ connection: SavedConnection) -> Bool {
        model.pendingRemovalName?.caseInsensitiveCompare(connection.name) == .orderedSame
    }

    @ViewBuilder
    private var emptyNotice: some View {
        if model.connections.isEmpty {
            Text("   no saved connections yet - add one above").foregroundColor(Theme.dim)
        }
    }

    private var fillerHeight: Int {
        // title(1) is outside auxiliaryCapacity's budget; the rows, the add button
        // and the empty notice sit inside it.
        let used = model.connections.count + 1 + (model.connections.isEmpty ? 1 : 0)
        return max(0, layout.auxiliaryCapacity - used)
    }
}
