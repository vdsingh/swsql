import SWSQLCore
import SwiftTUI

/// The whole screen: title bar, prompt, body, status line and key hints.
///
/// The prompt sits above the body rather than inside the results pane for two
/// reasons: SQL gets the full terminal width to be typed into, and it becomes the
/// first selectable control in the tree, which is where SwiftTUI puts the initial
/// keyboard focus.
struct RootView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        GeometryReader { size in
            screen(
                ScreenLayout(
                    width: size.width.finiteValue ?? ScreenLayout.minimumWidth,
                    height: size.height.finiteValue ?? ScreenLayout.minimumHeight
                )
            )
        }
    }

    @ViewBuilder
    private func screen(_ layout: ScreenLayout) -> some View {
        if !layout.isUsable {
            TooSmallView(layout: layout)
        } else if model.connectionState == .unconfigured {
            SetupView(model: model, layout: layout)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                TitleBarView(model: model, width: layout.width)
                PromptView(model: model, width: layout.width)
                EchoView(model: model, width: layout.width)
                BodyView(model: model, layout: layout)
                StatusBarView(model: model, width: layout.width)
                KeyHintsView(model: model, width: layout.width)
            }
        }
    }
}

/// Shown when the terminal cannot fit a legible layout.
private struct TooSmallView: View {
    let layout: ScreenLayout

    var body: some View {
        VStack(alignment: .leading) {
            Text("swsql needs a larger terminal").foregroundColor(Theme.warning).bold()
            Text("current  \(layout.width)×\(layout.height)").foregroundColor(Theme.dim)
            Text("minimum  \(ScreenLayout.minimumWidth)×\(ScreenLayout.minimumHeight)").foregroundColor(Theme.dim)
        }
        .padding(1)
    }
}

/// Sidebar, vertical rule and main pane, all sized explicitly.
private struct BodyView: View {
    @ObservedObject var model: AppModel
    let layout: ScreenLayout

    var body: some View {
        // Publishing the measured viewport back to the model is what lets paging
        // and scrolling work in terms of rows that are actually on screen.
        model.setViewport(rows: layout.gridRowCapacity)

        return HStack(alignment: .top, spacing: 0) {
            if layout.showsSidebar {
                SidebarView(model: model, width: layout.sidebarWidth, capacity: layout.sidebarListCapacity)
                VerticalRule(height: layout.bodyHeight)
            }
            MainPaneView(model: model, layout: layout)
        }
    }
}

/// A one column rule drawn as a stack of characters, which keeps its height
/// under our control instead of depending on how the stack proposes sizes.
struct VerticalRule: View {
    let height: Int

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(0..<max(1, height)), id: \.self) { _ in
                Text("│").foregroundColor(Theme.separator)
            }
        }
    }
}
