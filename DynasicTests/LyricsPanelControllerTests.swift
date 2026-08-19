import AppKit
import XCTest

@testable import dynasic

@MainActor
final class LyricsPanelControllerTests: XCTestCase {
    func testShowHideShowReusesSinglePanel() {
        let state = DynasicAppState()
        let defaults = UserDefaults(suiteName: "dynasic-panel-\(UUID().uuidString)")!
        let controller = LyricsPanelController(
            state: state,
            userDefaults: defaults,
            positionKey: "origin"
        )

        controller.show()
        let firstPanel = controller.panelForTesting
        controller.hide()
        controller.show()

        XCTAssertNotNil(firstPanel)
        XCTAssertTrue(firstPanel === controller.panelForTesting)
        XCTAssertTrue(controller.isVisible)
        controller.hide()
        XCTAssertFalse(controller.isVisible)
    }

    func testPanelUsesRequiredWindowConfiguration() {
        let state = DynasicAppState()
        let controller = LyricsPanelController(state: state)

        controller.show()
        let panel = try! XCTUnwrap(controller.panelForTesting)

        XCTAssertTrue(panel.styleMask.contains(.titled))
        XCTAssertTrue(panel.styleMask.contains(.fullSizeContentView))
        XCTAssertTrue(panel.styleMask.contains(.resizable))
        XCTAssertEqual(panel.titleVisibility, .hidden)
        XCTAssertTrue(panel.titlebarAppearsTransparent)
        XCTAssertTrue(panel.standardWindowButton(.closeButton)?.isHidden == true)
        XCTAssertEqual(panel.minSize, LyricsPanelController.minimumExpandedSize)
        XCTAssertEqual(panel.maxSize, LyricsPanelController.maximumExpandedSize)
        XCTAssertTrue(panel.isFloatingPanel)
        XCTAssertTrue(panel.collectionBehavior.contains(.canJoinAllSpaces))
        XCTAssertTrue(panel.collectionBehavior.contains(.fullScreenAuxiliary))
        XCTAssertTrue(panel.isMovableByWindowBackground)
    }

    func testPanelAppliesLiveInteractionSettings() {
        let defaults = UserDefaults(suiteName: "dynasic-panel-\(UUID().uuidString)")!
        let state = DynasicAppState(userDefaults: defaults)

        state.showLyrics()
        let controller = try! XCTUnwrap(state.panelControllerForTesting)
        let panel = try! XCTUnwrap(controller.panelForTesting)

        state.settings.isClickThrough = true
        state.settings.isAlwaysOnTop = false

        XCTAssertTrue(panel.ignoresMouseEvents)
        XCTAssertFalse(panel.isFloatingPanel)
        XCTAssertEqual(panel.level, .normal)
        state.hideLyrics()
    }

    func testPanelPersistsCompleteExpandedFrameAndRestoresItAfterCollapse() throws {
        let defaults = UserDefaults(suiteName: "dynasic-panel-\(UUID().uuidString)")!
        let controller = LyricsPanelController(
            state: DynasicAppState(userDefaults: defaults),
            userDefaults: defaults,
            positionKey: "frame",
            animationDuration: 0
        )

        controller.show()
        let panel = try XCTUnwrap(controller.panelForTesting)
        let expectedFrame = NSRect(x: 140, y: 180, width: 520, height: 240)
        panel.setFrame(expectedFrame, display: false)
        controller.finishUserMoveForTesting()

        controller.toggleCollapsed()
        XCTAssertTrue(controller.isCollapsed)
        XCTAssertEqual(panel.frame.size, LyricsPanelController.collapsedSize)
        XCTAssertEqual(panel.minSize, LyricsPanelController.collapsedSize)
        XCTAssertEqual(panel.maxSize, LyricsPanelController.collapsedSize)
        XCTAssertFalse(panel.ignoresMouseEvents)

        controller.toggleCollapsed()
        XCTAssertFalse(controller.isCollapsed)
        XCTAssertTrue(panel.styleMask.contains(.resizable))
        XCTAssertEqual(panel.minSize, LyricsPanelController.minimumExpandedSize)
        XCTAssertEqual(panel.frame, expectedFrame)

        let values = try XCTUnwrap(defaults.array(forKey: "frame") as? [Double])
        XCTAssertEqual(values.count, 4)
        XCTAssertEqual(values[0], expectedFrame.origin.x)
        XCTAssertEqual(values[1], expectedFrame.origin.y)
        XCTAssertEqual(values[2], expectedFrame.size.width)
        XCTAssertEqual(values[3], expectedFrame.size.height)
    }

    func testSavedExpandedFrameIsKeptInsideAVisibleScreen() throws {
        let screen = try XCTUnwrap(NSScreen.main)
        let visible = screen.visibleFrame
        let defaults = UserDefaults(suiteName: "dynasic-panel-\(UUID().uuidString)")!
        defaults.set(
            [visible.maxX - 100, visible.midY, 620, 260],
            forKey: "frame"
        )
        let controller = LyricsPanelController(
            state: DynasicAppState(userDefaults: defaults),
            userDefaults: defaults,
            positionKey: "frame"
        )

        controller.show()
        let panel = try XCTUnwrap(controller.panelForTesting)

        XCTAssertTrue(NSScreen.screens.contains { $0.visibleFrame.contains(panel.frame) })
    }

    func testShowingExistingPanelBringsItsFrameBackOnScreen() throws {
        let defaults = UserDefaults(suiteName: "dynasic-panel-\(UUID().uuidString)")!
        let controller = LyricsPanelController(
            state: DynasicAppState(userDefaults: defaults),
            userDefaults: defaults
        )

        controller.show()
        let panel = try XCTUnwrap(controller.panelForTesting)
        panel.setFrameOrigin(NSPoint(x: panel.frame.minX, y: -10_000))
        controller.hide()
        controller.show()

        XCTAssertTrue(NSScreen.screens.contains { $0.visibleFrame.contains(panel.frame) })
    }

    func testClickThroughIsRestoredOnlyAfterExpanding() throws {
        let defaults = UserDefaults(suiteName: "dynasic-panel-\(UUID().uuidString)")!
        let state = DynasicAppState(userDefaults: defaults)
        state.settings.isClickThrough = true
        let controller = LyricsPanelController(
            state: state,
            userDefaults: defaults,
            animationDuration: 0
        )

        controller.show()
        let panel = try XCTUnwrap(controller.panelForTesting)
        XCTAssertTrue(panel.ignoresMouseEvents)

        controller.toggleCollapsed()
        XCTAssertFalse(panel.ignoresMouseEvents)
        XCTAssertTrue(panel.styleMask.contains(.resizable))
        XCTAssertEqual(panel.minSize, LyricsPanelController.collapsedSize)
        XCTAssertEqual(panel.maxSize, LyricsPanelController.collapsedSize)

        controller.toggleCollapsed()
        XCTAssertTrue(panel.ignoresMouseEvents)
        XCTAssertTrue(panel.styleMask.contains(.resizable))
    }

    func testStickyToCornerRunsOnlyWhenUserMoveFinishes() throws {
        let defaults = UserDefaults(suiteName: "dynasic-panel-\(UUID().uuidString)")!
        let state = DynasicAppState(userDefaults: defaults)
        state.settings.isStickyToCorner = true
        let controller = LyricsPanelController(state: state, userDefaults: defaults)

        controller.show()
        let panel = try XCTUnwrap(controller.panelForTesting)
        let freeFrame = NSRect(x: 300, y: 300, width: 280, height: 120)
        panel.setFrame(freeFrame, display: false)
        XCTAssertEqual(panel.frame.origin, freeFrame.origin)

        controller.finishUserMoveForTesting()
        let visibleFrames = NSScreen.screens.map(\.visibleFrame)
        let isAtCorner = visibleFrames.contains { visible in
            let frame = panel.frame
            let xMatches = abs(frame.minX - visible.minX) < 0.5 || abs(frame.maxX - visible.maxX) < 0.5
            let yMatches = abs(frame.minY - visible.minY) < 0.5 || abs(frame.maxY - visible.maxY) < 0.5
            return xMatches && yMatches
        }
        XCTAssertTrue(isAtCorner)
    }
}
