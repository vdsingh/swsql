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

    /// Lines of chrome outside the body: title bar, prompt, statement echo,
    /// status line and key hints.
    public static let chromeHeight = 5

    /// Lines the data pane spends on its own furniture: column header, rule and
    /// the row of controls underneath.
    public static let dataPaneChromeHeight = 3

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
        max(1, height - ScreenLayout.chromeHeight)
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
