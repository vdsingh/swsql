import SWSQLCore
import SwiftTUI

/// Everything to the right of the sidebar: whichever pane is currently open.
struct MainPaneView: View {
    @ObservedObject var model: AppModel
    let layout: ScreenLayout

    /// The controls row lives here rather than inside each pane so that switching
    /// panes never tears down the buttons the keyboard might be sitting on.
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            pane
            ControlsRow(model: model, width: layout.mainWidth)
        }
    }

    @ViewBuilder
    private var pane: some View {
        switch model.pane {
        case .data:
            DataPaneView(model: model, layout: layout)
        case .structure:
            StructurePaneView(model: model, layout: layout)
        case .rowDetail:
            RowDetailPaneView(model: model, layout: layout)
        case .history:
            HistoryPaneView(model: model, layout: layout)
        case .connections:
            ConnectionsPaneView(model: model, layout: layout)
        case .help:
            HelpPaneView(model: model, layout: layout)
        }
    }
}

/// The SQL entry line. SwiftTUI's text field clears itself on submit, so the
/// statement that ran is echoed on the line below instead of staying in the field.
struct PromptView: View {
    @ObservedObject var model: AppModel
    let width: Int

    var body: some View {
        HStack(spacing: 0) {
            Text(" sql> ").foregroundColor(Theme.accent).bold()
            TextField(placeholder: "type a statement and press ⏎") { statement in
                model.run(statement)
            }
            .frame(width: Extended(max(1, width - 6)))
        }
    }
}

/// A dim recap of the statement that produced what is on screen.
struct EchoView: View {
    @ObservedObject var model: AppModel
    let width: Int

    var body: some View {
        Text(DisplayText.pad(" " + text, to: width, alignment: .left))
            .foregroundColor(Theme.dim)
            .italic()
    }

    private var text: String {
        guard !model.lastStatement.isEmpty else {
            return "no statement run yet - pick a table on the left, or type one above"
        }
        return DisplayText.truncate(DisplayText.singleLine(model.lastStatement), to: max(1, width - 2))
    }
}
