import SWSQLCore
import SwiftTUI

/// The add-a-connection screen: a name, a URL, and whether it is production.
///
/// Shown full-screen whenever there is no connection target yet - on first run
/// with nothing saved, or when adding another connection from the list. swsql
/// remembers what is entered here once it connects, so later launches need no
/// argument and no PG* environment.
struct SetupView: View {
    @ObservedObject var model: AppModel
    let layout: ScreenLayout

    /// Forms the URL field accepts, one per line, purely as a reminder.
    private static let examples = [
        "postgres://user:password@host:5432/dbname",
        "postgresql://alice@db.internal/shop?sslmode=require",
        "host=db.internal user=alice dbname=shop",
        "shop                          (a database on the local server)"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TitleBarView(model: model, width: layout.width)
            content
            Filler(height: fillerHeight, width: layout.width)
            StatusBarView(model: model, width: layout.width)
            Text(DisplayText.pad("  ⏎ in the url field connects   ·   empty url uses PG* environment defaults   ·   ^C quit", to: layout.width, alignment: .left))
                .foregroundColor(Theme.dim)
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            blank
            Text("  Add a connection").foregroundColor(Theme.accent).bold()
            field(label: "name> ", placeholder: "an optional label, e.g. prod or staging") { input in
                model.setDraftName(input)
            }
            field(label: " url> ", placeholder: "paste a connection URL and press ⏎") { input in
                if input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    model.useEnvironmentDefaults()
                } else {
                    model.addConnection(url: input)
                }
            }
            HStack(spacing: 2) {
                Text("      ")
                Button(productionLabel, action: { model.toggleDraftProduction() })
                    .foregroundColor(model.draftIsProduction ? Theme.warning : Theme.dim)
                cancelButton
            }
            Text("  " + DisplayText.truncate(draftSummary, to: max(1, layout.width - 2)))
                .foregroundColor(model.draftIsProduction ? Theme.warning : Theme.dim)
            blank
            Text("  Examples").foregroundColor(Theme.dim)
            ForEach(SetupView.examples.indexed) { example in
                Text("    " + DisplayText.truncate(example.value, to: max(1, layout.width - 4)))
                    .foregroundColor(Theme.dim)
            }
        }
    }

    @ViewBuilder
    private var cancelButton: some View {
        // Only offer to cancel when there is already a connection to go back to.
        if !model.connections.isEmpty {
            Button("Cancel", action: { model.cancelAdd() }).foregroundColor(Theme.dim)
        }
    }

    private func field(label: String, placeholder: String, onSubmit: @escaping (String) -> Void) -> some View {
        HStack(spacing: 0) {
            Text("  \(label)").foregroundColor(Theme.accent).bold()
            TextField(placeholder: placeholder, action: onSubmit)
                .frame(width: Extended(max(1, layout.width - label.count - 2)))
        }
    }

    private var productionLabel: String {
        model.draftIsProduction ? "[x] production" : "[ ] production"
    }

    private var draftSummary: String {
        let name = model.draftName.isEmpty ? "(named from the database)" : "\"\(model.draftName)\""
        let prod = model.draftIsProduction ? "   ⚠ will be marked PRODUCTION" : ""
        return "saving as \(name)\(prod)"
    }

    /// A full-width blank line, so the screen paints solidly rather than leaving
    /// the terminal's previous contents showing through the gaps.
    private var blank: some View {
        Text(String(repeating: " ", count: max(1, layout.width)))
    }

    /// Lines the `content` stack paints, so the filler can hold the screen height
    /// steady: two blanks, the heading, the name and url fields, the toggle row,
    /// the summary, the "Examples" label and the example lines.
    private var contentLineCount: Int {
        2 + 1 + 2 + 1 + 1 + 1 + SetupView.examples.count
    }

    /// title(1) + content + filler + status(1) + hint(1) == layout.height.
    private var fillerHeight: Int {
        max(0, layout.height - 1 - contentLineCount - 2)
    }
}
