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

        XCTAssertTrue(panel.styleMask.contains(.borderless))
        XCTAssertTrue(panel.isFloatingPanel)
        XCTAssertTrue(panel.collectionBehavior.contains(.canJoinAllSpaces))
        XCTAssertTrue(panel.collectionBehavior.contains(.fullScreenAuxiliary))
        XCTAssertTrue(panel.isMovableByWindowBackground)
    }
}
