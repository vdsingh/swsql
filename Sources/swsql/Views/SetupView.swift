import SWSQLCore
import SwiftTUI

/// The first-run screen: paste a connection URL, which swsql then remembers so
/// the next launch needs neither an argument nor any PG* environment.
///
/// Shown whenever there is no connection target yet - on first run with nothing
/// saved, or after choosing "Edit URL" from a failed connection.
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
        // SwiftTUI's ViewBuilder tops out at ten children per stack, so the body
        // of the screen is grouped into one nested stack of its own.
        VStack(alignment: .leading, spacing: 0) {
            TitleBarView(model: model, width: layout.width)
            content
            Filler(height: fillerHeight, width: layout.width)
            StatusBarView(model: model, width: layout.width)
            Text(DisplayText.pad("  ⏎ connect     ⏎ on an empty line uses PG* environment defaults     ^C quit", to: layout.width, alignment: .left))
                .foregroundColor(Theme.dim)
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            blank
            Text("  Connect to PostgreSQL").foregroundColor(Theme.accent).bold()
            blank
            HStack(spacing: 0) {
                Text("  url> ").foregroundColor(Theme.accent).bold()
                TextField(placeholder: "paste a connection URL and press ⏎") { input in
                    if input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        model.useEnvironmentDefaults()
                    } else {
                        model.configure(input)
                    }
                }
                .frame(width: Extended(max(1, layout.width - 7)))
            }
            blank
            Text("  Examples").foregroundColor(Theme.dim)
            ForEach(SetupView.examples.indexed) { example in
                Text("    " + DisplayText.truncate(example.value, to: max(1, layout.width - 4)))
                    .foregroundColor(Theme.dim)
            }
            blank
            Text(DisplayText.truncate("  Saved to ~/.config/swsql/connection, readable only by you, once it connects.", to: max(1, layout.width)))
                .foregroundColor(Theme.dim)
        }
    }

    /// A full-width blank line, so the screen paints solidly rather than leaving
    /// the terminal's previous contents showing through the gaps.
    private var blank: some View {
        Text(String(repeating: " ", count: max(1, layout.width)))
    }

    /// Lines the `content` stack paints: four blanks, the heading, the `url>`
    /// field, the "Examples" label, the example lines and the save-location note.
    private var contentLineCount: Int {
        4 + 1 + 1 + 1 + SetupView.examples.count + 1
    }

    /// Holds the screen height steady by filling everything between the note and
    /// the status line, so the whole layout is exactly `layout.height` tall:
    /// title(1) + content + filler + status(1) + hint(1).
    private var fillerHeight: Int {
        max(0, layout.height - 1 - contentLineCount - 2)
    }
}
