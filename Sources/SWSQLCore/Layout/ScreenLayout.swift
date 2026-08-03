import Foundation

/// Divides the terminal into the regions the app draws into.
///
/// The whole screen is sized explicitly rather than left to flexible frames, so
/// every string can be padded to a width that is known before rendering. That is
/// what keeps columns lined up when the terminal is resized.
public struct ScreenLayout: Equatable {
    /// Below this the app shows a "make the window bigger" message instead of a
    /// mangled layout.
    public static let minimumWidth = 54
    public static let minimumHeight = 12

    public static let preferredSidebarWidth = 30
    /// Hide the sidebar rather than squeeze the results into nothing.
    public static let sidebarHiddenBelowWidth = 78

    /// Preferred height of the multi-line SQL editor, before clamping to the terminal.
    public static let preferredEditorHeight = 6

    /// Lines the data pane spends on its own furniture: column header, rule and
    /// the row of controls underneath.
    public static let dataPaneChromeHeight = 3

    /// Lines the SQL editor occupies: enough for a few lines of a query, but never
    /// so many that the result grid is left with no room.
    public var editorHeight: Int {
        max(2, min(ScreenLayout.preferredEditorHeight, height - 8))
    }

    /// Lines of chrome outside the body: title bar (1), the editor pane, its
    /// toolbar (1), the status line (1) and the key hints (1).
    public var chromeHeight: Int {
        editorHeight + 4
    }

    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) {
        self.width = max(0, width)
        self.height = max(0, height)
    }

    public var isUsable: Bool {
        width >= ScreenLayout.minimumWidth && height >= ScreenLayout.minimumHeight
    }

    public var showsSidebar: Bool {
        width >= ScreenLayout.sidebarHiddenBelowWidth
    }

    public var sidebarWidth: Int {
        showsSidebar ? min(ScreenLayout.preferredSidebarWidth, width / 3) : 0
    }

    /// The one column vertical rule between sidebar and main pane.
    public var dividerWidth: Int { showsSidebar ? 1 : 0 }

    public var mainWidth: Int {
        max(1, width - sidebarWidth - dividerWidth)
    }

    public var bodyHeight: Int {
        max(1, height - chromeHeight)
    }

    /// Rows of the object list, after its own header and filter field.
    public var sidebarListCapacity: Int {
        max(1, bodyHeight - 2)
    }

    /// Lines a pane may use before its own row of controls.
    public var paneContentHeight: Int {
        max(1, bodyHeight - 1)
    }

    /// Rows of result data the grid can draw.
    public var gridRowCapacity: Int {
        max(1, bodyHeight - ScreenLayout.dataPaneChromeHeight)
    }

    /// Lines available to a pane with its own title line and row of controls,
    /// such as help, history or row detail.
    public var auxiliaryCapacity: Int {
        max(1, bodyHeight - 2)
    }
}
