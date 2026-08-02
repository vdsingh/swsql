import XCTest
@testable import SWSQLCore

final class ScreenLayoutTests: XCTestCase {
    func testTheBodyIsExactlyFilledByItsPanes() {
        for width in [54, 78, 100, 200] {
            for height in [12, 24, 40, 80] {
                let layout = ScreenLayout(width: width, height: height)

                XCTAssertEqual(
                    layout.paneContentHeight + 1,
                    layout.bodyHeight,
                    "a pane plus its controls row must fill the body at \(width)×\(height)"
                )
                XCTAssertEqual(
                    layout.gridRowCapacity + 2,
                    layout.paneContentHeight,
                    "the grid plus its header and rule must fill the pane at \(width)×\(height)"
                )
                XCTAssertEqual(
                    layout.auxiliaryCapacity + 1,
                    layout.paneContentHeight,
                    "an auxiliary pane plus its title must fill the pane at \(width)×\(height)"
                )
            }
        }
    }

    func testSidebarAndMainPaneCoverTheFullWidth() {
        for width in [54, 77, 78, 120, 300] {
            let layout = ScreenLayout(width: width, height: 40)
            XCTAssertEqual(
                layout.sidebarWidth + layout.dividerWidth + layout.mainWidth,
                width,
                "columns must add up at width \(width)"
            )
        }
    }

    func testSidebarIsHiddenOnNarrowTerminals() {
        XCTAssertFalse(ScreenLayout(width: 77, height: 40).showsSidebar)
        XCTAssertTrue(ScreenLayout(width: 78, height: 40).showsSidebar)
        XCTAssertEqual(ScreenLayout(width: 77, height: 40).dividerWidth, 0)
    }

    func testUsabilityThreshold() {
        XCTAssertFalse(ScreenLayout(width: 53, height: 40).isUsable)
        XCTAssertFalse(ScreenLayout(width: 80, height: 11).isUsable)
        XCTAssertTrue(ScreenLayout(width: 54, height: 12).isUsable)
    }

    func testDegenerateSizesStayPositive() {
        let layout = ScreenLayout(width: 0, height: 0)

        XCTAssertGreaterThan(layout.mainWidth, 0)
        XCTAssertGreaterThan(layout.bodyHeight, 0)
        XCTAssertGreaterThan(layout.gridRowCapacity, 0)
        XCTAssertFalse(layout.isUsable)
    }
}
