import SWSQLCore
import SwiftTUI

/// The multi-line SQL editor and its toolbar, sitting under the title bar.
///
/// The editor is the first selectable control, so focus and typed input land
/// here on launch. Return inserts a newline; Ctrl-R (or the Run button) executes
/// the whole buffer. Arrow keys move the cursor and fall through to the toolbar
/// once the cursor reaches the last line.
struct EditorPaneView: View {
    @ObservedObject var model: AppModel
    let layout: ScreenLayout

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextEditor(
                document: model.document,
                placeholder: "type a SQL statement  —  ⌃R or Run ▶ to execute,  ⏎ for a new line",
                onRun: { model.runCurrentQuery() }
            )
            .frame(width: Extended(layout.width), height: Extended(layout.editorHeight))
            .background(Color.xterm(white: 2))

            toolbar
        }
    }

    private var toolbar: some View {
        HStack(spacing: 1) {
            Text(" ")
            Button("Run ▶", action: { model.runCurrentQuery() }).foregroundColor(Theme.success).bold()
            Button("Clear", action: { model.clearEditor() }).foregroundColor(Theme.dim)
            Text(DisplayText.pad("   ⌃R run  ·  ⏎ newline  ·  ↑↓←→ move the cursor", to: max(1, layout.width - 18), alignment: .left))
                .foregroundColor(Theme.dim)
        }
    }
}
