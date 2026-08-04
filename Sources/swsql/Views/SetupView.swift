import SWSQLCore
import SwiftTUI

/// The add-a-connection screen: a name, a URL, and whether it is production.
///
/// Laid out as a small form - a titled rule, numbered steps, shaded input boxes
/// with an accent bar, and a segmented environment toggle - so what needs your
/// input reads at a glance and the required field stands apart from the optional
/// one. Shown full-screen whenever there is no connection target yet.
struct SetupView: View {
    @ObservedObject var model: AppModel
    let layout: ScreenLayout

    private var inputBackground: Color { Color.xterm(white: 3) }
    private var nameFieldWidth: Int { max(16, min(48, layout.width - 12)) }
    private var urlFieldWidth: Int { max(24, layout.width - 10) }
    /// The discrete fields sit under a label column, so they get a little less room.
    private var partFieldWidth: Int { max(16, min(40, layout.width - 24)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TitleBarView(model: model, width: layout.width)
            blank
            headerRule
            blank
            steps
            Filler(height: fillerHeight, width: layout.width)
            ForEach(examplesLines.indexed) { line in
                Text(DisplayText.pad("  " + line.value, to: layout.width, alignment: .left)).foregroundColor(Theme.dim)
            }
            StatusBarView(model: model, width: layout.width)
            ForEach(hintLines.indexed) { line in
                Text(DisplayText.pad("  " + line.value, to: layout.width, alignment: .left)).foregroundColor(Theme.dim)
            }
        }
    }

    // MARK: - The form

    private var steps: some View {
        VStack(alignment: .leading, spacing: 0) {
            stepLabel(number: "①", title: "Name", badge: "optional", badgeColor: Theme.dim)
            nameField
            blank
            connectionStep
            blank
            stepLabel(number: "③", title: "Environment", badge: "", badgeColor: Theme.dim)
            environmentToggle
        }
    }

    /// Step ②: choose how to give the connection - a whole URL, or the individual
    /// fields - then show whichever input that choice calls for.
    private var connectionStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 1) {
                Text("  ②").foregroundColor(Theme.accent).bold()
                Text("Connection").foregroundColor(Theme.strong).bold()
                Text("  ").foregroundColor(Theme.dim)
                Button(" URL ", action: { model.useURLInput() })
                    .foregroundColor(model.draftInput == .url ? Theme.accent : Theme.dim)
                    .bold()
                Text("/").foregroundColor(Theme.dim)
                Button(" fields ", action: { model.useFieldsInput() })
                    .foregroundColor(model.draftInput == .fields ? Theme.accent : Theme.dim)
                    .bold()
                Text(model.draftInput == .url ? "  press ⏎ in the box to connect" : "  fill in what you know, then connect")
                    .foregroundColor(Theme.dim)
            }
            if model.draftInput == .url {
                urlField
            } else {
                fieldsForm
            }
        }
    }

    private func stepLabel(number: String, title: String, badge: String, badgeColor: Color) -> some View {
        HStack(spacing: 1) {
            Text("  \(number)").foregroundColor(Theme.accent).bold()
            Text(title).foregroundColor(Theme.strong).bold()
            Text(badge.isEmpty ? "" : "  \(badge)").foregroundColor(badgeColor).bold()
        }
    }

    @ViewBuilder
    private var nameField: some View {
        if model.draftName.isEmpty {
            HStack(spacing: 0) {
                Text("    ▎ ").foregroundColor(Theme.accent)
                TextField(placeholder: "type a name and press ⏎  (e.g. prod, staging)") { input in
                    model.setDraftName(input)
                }
                .frame(width: Extended(nameFieldWidth))
                .background(inputBackground)
            }
        } else {
            HStack(spacing: 1) {
                Text("    ▎ ").foregroundColor(Theme.accent)
                Text(DisplayText.pad(" \(model.draftName) ", to: nameFieldWidth, alignment: .left))
                    .foregroundColor(Theme.strong)
                    .background(inputBackground)
                Button("change", action: { model.clearDraftName() }).foregroundColor(Theme.dim)
            }
        }
    }

    private var urlField: some View {
        HStack(spacing: 0) {
            Text("    ▎ ").foregroundColor(Theme.accent).bold()
            TextField(placeholder: "postgres://user@host:5432/dbname   (or host=… dbname=…, or a db name)") { input in
                if input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    model.useEnvironmentDefaults()
                } else {
                    model.addConnection(url: input)
                }
            }
            .frame(width: Extended(urlFieldWidth))
            .background(inputBackground)
        }
    }

    /// The individual-fields form: host, port, user, password, database, then a
    /// button that assembles them and connects. Each field commits on ⏎ (mirroring
    /// the name field) so nothing depends on the order they are filled in.
    private var fieldsForm: some View {
        VStack(alignment: .leading, spacing: 0) {
            partField(label: "host", placeholder: "localhost", value: model.draftHost,
                      set: model.setDraftHost, clear: model.clearDraftHost)
            partField(label: "port", placeholder: "5432", value: model.draftPort,
                      set: model.setDraftPort, clear: model.clearDraftPort)
            partField(label: "user", placeholder: "your role", value: model.draftUser,
                      set: model.setDraftUser, clear: model.clearDraftUser)
            partField(label: "password", placeholder: "leave blank to be prompted / use ~/.pgpass",
                      value: model.draftPassword, display: String(repeating: "•", count: model.draftPassword.count),
                      set: model.setDraftPassword, clear: model.clearDraftPassword)
            partField(label: "database", placeholder: "dbname", value: model.draftDatabase,
                      set: model.setDraftDatabase, clear: model.clearDraftDatabase)
            connectButton
        }
    }

    /// One labelled field. Empty, it shows an input; filled, it shows the stored
    /// value (masked for the password) with a `change` link, just like the name
    /// field. `display` overrides what the filled state shows.
    @ViewBuilder
    private func partField(
        label: String,
        placeholder: String,
        value: String,
        display: String? = nil,
        set: @escaping (String) -> Void,
        clear: @escaping () -> Void
    ) -> some View {
        if value.isEmpty {
            HStack(spacing: 0) {
                Text("    ▎ ").foregroundColor(Theme.accent)
                Text(DisplayText.pad(label, to: 9, alignment: .left)).foregroundColor(Theme.dim)
                TextField(placeholder: placeholder) { set($0) }
                    .frame(width: Extended(partFieldWidth))
                    .background(inputBackground)
            }
        } else {
            HStack(spacing: 1) {
                Text("    ▎ ").foregroundColor(Theme.accent)
                Text(DisplayText.pad(label, to: 8, alignment: .left)).foregroundColor(Theme.dim)
                Text(DisplayText.pad(" \(display ?? value) ", to: partFieldWidth, alignment: .left))
                    .foregroundColor(Theme.strong)
                    .background(inputBackground)
                Button("change", action: clear).foregroundColor(Theme.dim)
            }
        }
    }

    private var connectButton: some View {
        HStack(spacing: 1) {
            Text("    ")
            Button(" ● connect ▶ ", action: { model.addConnectionFromFields() })
                .foregroundColor(Theme.accent)
                .bold()
                .background(inputBackground)
        }
    }

    private var environmentToggle: some View {
        HStack(spacing: 1) {
            Text("      ")
            Button(" staging ", action: { model.setDraftProduction(false) })
                .foregroundColor(model.draftIsProduction ? Theme.dim : Theme.success)
                .bold()
            Text("/").foregroundColor(Theme.dim)
            Button(" ⚠ production ", action: { model.setDraftProduction(true) })
                .foregroundColor(model.draftIsProduction ? Theme.failure : Theme.dim)
                .bold()
            cancelButton
        }
    }

    @ViewBuilder
    private var cancelButton: some View {
        // Only offer to cancel when there is already a connection to go back to.
        if !model.connections.isEmpty {
            Text("        ").foregroundColor(Theme.dim)
            Button("‹ cancel", action: { model.cancelAdd() }).foregroundColor(Theme.dim)
        }
    }

    // MARK: - Chrome

    private var headerRule: some View {
        let title = "Add a connection"
        let fill = max(0, layout.width - 5 - title.count - 1)
        return HStack(spacing: 0) {
            Text("  ── ").foregroundColor(Theme.separator)
            Text(title).foregroundColor(Theme.accent).bold()
            Text(" " + String(repeating: "─", count: fill)).foregroundColor(Theme.separator)
        }
    }

    // Prose that can outrun a narrow terminal is wrapped onto extra lines rather
    // than truncated, so nothing important is cut off.
    private var examplesText: String {
        "Examples:  postgres://user@host/db  ·  postgresql://alice@db/shop?sslmode=require  ·  host=db dbname=shop  ·  mydb"
    }
    private var hintText: String {
        "URL / fields chooses how to enter details  ·  an empty URL uses your PG* environment  ·  ^C quit"
    }
    private var examplesLines: [String] { DisplayText.wrap(examplesText, to: max(1, layout.width - 2)) }
    private var hintLines: [String] { DisplayText.wrap(hintText, to: max(1, layout.width - 2)) }

    private var blank: some View {
        Text(String(repeating: " ", count: max(1, layout.width)))
    }

    /// Lines the form occupies: name label + field + blank (3), the connection
    /// step's own label (1) plus its input - one URL box, or five fields and a
    /// connect button (6) - then a blank and the two environment lines (3).
    private var stepsLineCount: Int {
        model.draftInput == .url ? 8 : 13
    }

    /// title(1) + blank(1) + rule(1) + blank(1) + steps + filler + examples +
    /// status(1) + hint == layout.height, with examples and hint each wrapping to
    /// however many lines they need.
    private var fillerHeight: Int {
        max(0, layout.height - 5 - stepsLineCount - examplesLines.count - hintLines.count)
    }
}
