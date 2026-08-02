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
                    label: {
                        Text(row(for: entry.value))
                            .foregroundColor(entry.value.isProduction ? Theme.warning : Theme.text)
                    }
                )
            }
            Button("  ＋ Add a connection", action: { model.beginAddConnection() })
                .foregroundColor(Theme.accent)
            emptyNotice
            Filler(height: fillerHeight, width: layout.mainWidth)
        }
    }

    /// One connection as a single line: an active marker, the name, its target and
    /// a production tag.
    private func row(for connection: SavedConnection) -> String {
        let active = model.activeConnection?.name.caseInsensitiveCompare(connection.name) == .orderedSame
        let marker = active ? "●" : " "
        let tag = connection.isProduction ? "  ⚠ PRODUCTION" : ""
        let name = DisplayText.pad(connection.name, to: 18, alignment: .left)
        let detail = DisplayText.singleLine(connection.connectionString)
        let room = max(1, layout.mainWidth - 18 - tag.count - 6)
        return " \(marker) \(name)  \(DisplayText.truncate(detail, to: room))\(tag)"
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
