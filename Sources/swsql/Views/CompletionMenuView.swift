import SWSQLCore
import SwiftTUI

/// The autocomplete dropdown, drawn as a bordered strip directly under the editor
/// when there are suggestions. The selected row is highlighted; `↑↓` pick it,
/// `⏎`/`Tab` insert it, `Esc` closes.
struct CompletionMenuView: View {
    @ObservedObject var model: AppModel
    let width: Int

    /// Rows the menu occupies: the two border lines plus one per suggestion.
    static func height(for count: Int) -> Int { count > 0 ? count + 2 : 0 }

    @ViewBuilder
    var body: some View {
        if !model.completions.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text(border(left: "┌", right: "┐", title: " complete ")).foregroundColor(Theme.separator)
                ForEach(model.completions.indexed) { entry in
                    Text(row(entry.value))
                        .foregroundColor(entry.id == model.completionIndex ? Theme.headerForeground : Theme.text)
                        .background(entry.id == model.completionIndex ? Theme.accent : Color.default)
                }
                Text(border(left: "└", right: "┘", title: "")).foregroundColor(Theme.separator)
            }
            // Floating over the grid, the menu must not let the cells behind
            // it shine through.
            .background(Color.default)
        }
    }

    private func border(left: String, right: String, title: String) -> String {
        let fill = max(0, width - 2 - title.count)
        return left + title + String(repeating: "─", count: fill) + right
    }

    private func row(_ item: CompletionItem) -> String {
        let marker = "▸ "
        let inner = max(1, width - 4) // between "│ " and " │"
        let nameField = DisplayText.pad(marker + item.text, to: min(30, max(1, inner - 12)), alignment: .left)
        let detail = DisplayText.truncate(item.detail, to: max(0, inner - nameField.count - 1))
        let middle = DisplayText.pad(nameField + " " + detail, to: inner, alignment: .left)
        return "│ " + middle + " │"
    }
}
