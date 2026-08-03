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

