import AppKit
import LyricsCore
import SwiftUI
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
        let defaults = UserDefaults(suiteName: "dynasic-panel-\(UUID().uuidString)")!
        let state = DynasicAppState(userDefaults: defaults)
        let controller = LyricsPanelController(state: state, userDefaults: defaults)

        controller.show()
        let panel = try! XCTUnwrap(controller.panelForTesting)

        XCTAssertTrue(panel.styleMask.contains(.titled))
        XCTAssertTrue(panel.styleMask.contains(.fullSizeContentView))
        XCTAssertTrue(panel.styleMask.contains(.resizable))
        XCTAssertEqual(panel.titleVisibility, .hidden)
        XCTAssertTrue(panel.titlebarAppearsTransparent)
        XCTAssertEqual(panel.titlebarSeparatorStyle, .none)
        XCTAssertTrue(panel.standardWindowButton(.closeButton)?.isHidden == true)
        XCTAssertTrue(panel.standardWindowButton(.miniaturizeButton)?.isHidden == true)
        XCTAssertTrue(panel.standardWindowButton(.zoomButton)?.isHidden == true)
        let hostingView = try! XCTUnwrap(panel.contentView as? NSHostingView<LyricsPanelView>)
        XCTAssertTrue(hostingView.sizingOptions.isEmpty)
        XCTAssertTrue(hostingView.acceptsFirstMouse(for: nil))
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

    func testClickMakesPanelFullyOpaqueUntilItLosesFocus() throws {
        let defaults = UserDefaults(suiteName: "dynasic-panel-\(UUID().uuidString)")!
        let state = DynasicAppState(userDefaults: defaults)
        state.settings.lyricsOpacity = 0.35
        let controller = LyricsPanelController(state: state, userDefaults: defaults)
        controller.show()
        defer { controller.hide() }
        let panel = try XCTUnwrap(controller.panelForTesting)
        XCTAssertEqual(controller.displayedOpacity, 0.35)

        panel.sendEvent(mouseEvent(.leftMouseDown, at: NSPoint(x: 20, y: 20), for: panel))

        XCTAssertTrue(controller.hasKeyboardFocus)
        XCTAssertEqual(controller.displayedOpacity, 1)
        state.settings.lyricsOpacity = 0.6
        XCTAssertEqual(controller.displayedOpacity, 1)

        panel.resignKey()

        XCTAssertFalse(controller.hasKeyboardFocus)
        XCTAssertEqual(controller.displayedOpacity, 0.6)
        XCTAssertEqual(state.settings.lyricsOpacity, 0.6)
    }

    func testClickThroughKeepsActualControlsInteractiveAcrossLayoutsAndRotation() throws {
        let defaults = UserDefaults(suiteName: "dynasic-panel-\(UUID().uuidString)")!
        let state = DynasicAppState(userDefaults: defaults)
        state.settings.isClickThrough = true
        let controller = LyricsPanelController(
            state: state,
            userDefaults: defaults,
            animationDuration: 0
        )
        controller.show()
        defer { controller.hide() }
        let panel = try XCTUnwrap(controller.panelForTesting)

        for layout in LyricsPanelLayout.allCases {
            state.settings.lyricsPanelLayout = layout
            for _ in 0..<2 {
                panel.contentView?.layoutSubtreeIfNeeded()
                let controls = controller.controlRegionFrames
                XCTAssertEqual(controls.count, 2, "Quit and toolbar regions must be registered")
                for frame in controls {
                    XCTAssertGreaterThan(frame.width, 0)
                    XCTAssertGreaterThan(frame.height, 0)
                    controller.updatePointerLocation(NSPoint(x: frame.midX, y: frame.midY))
                    XCTAssertFalse(panel.ignoresMouseEvents)
                }
                controller.updatePointerLocation(NSPoint(x: panel.frame.midX, y: panel.frame.midY))
                XCTAssertTrue(panel.ignoresMouseEvents)
                controller.rotateContent()
            }
        }

        panel.setFrameOrigin(NSPoint(x: panel.frame.minX + 30, y: panel.frame.minY + 30))
        let movedControl = try XCTUnwrap(controller.controlRegionFrames.first)
        controller.updatePointerLocation(NSPoint(x: movedControl.midX, y: movedControl.midY))
        XCTAssertFalse(panel.ignoresMouseEvents)
    }

    func testPointerMonitorsFollowVisibilityClickThroughAndCollapse() throws {
        let defaults = UserDefaults(suiteName: "dynasic-panel-\(UUID().uuidString)")!
        let state = DynasicAppState(userDefaults: defaults)
        state.settings.isClickThrough = true
        let controller = LyricsPanelController(
            state: state,
            userDefaults: defaults,
            animationDuration: 0
        )
        XCTAssertFalse(controller.isMonitoringPointerForTesting)
        controller.show()
        defer { controller.hide() }
        XCTAssertTrue(controller.isMonitoringPointerForTesting)

        controller.toggleCollapsed()
        XCTAssertFalse(controller.isMonitoringPointerForTesting)
        XCTAssertFalse(try XCTUnwrap(controller.panelForTesting).ignoresMouseEvents)
        controller.toggleCollapsed()
        XCTAssertTrue(controller.isMonitoringPointerForTesting)

        controller.hide()
        XCTAssertFalse(controller.isMonitoringPointerForTesting)
        controller.show()
        XCTAssertTrue(controller.isMonitoringPointerForTesting)
        controller.setClickThrough(false)
        XCTAssertFalse(controller.isMonitoringPointerForTesting)
        XCTAssertFalse(try XCTUnwrap(controller.panelForTesting).ignoresMouseEvents)
    }

    func testNewAuxiliaryWindowsAreReadyAndSelectedBeforeActivation() throws {
        let state = DynasicAppState(
            userDefaults: UserDefaults(suiteName: "dynasic-windows-\(UUID().uuidString)")!
        )
        for destination in DynasicAuxiliaryWindow.allCases {
            let window = FocusRecordingWindow(
                contentRect: NSRect(x: 100, y: 100, width: 360, height: 320),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.isReleasedWhenClosed = false
            defer { window.close() }

            var activationCount = 0
            var creationCount = 0
            let controller = DynasicAuxiliaryWindowController(
                activateApplication: { _ in
                    XCTAssertEqual(window.focusRequests, ["main", "key", "front"])
                    XCTAssertEqual(window.identifier, destination.identifier)
                    activationCount += 1
                },
                windowFactory: { requestedDestination, requestedState in
                    XCTAssertEqual(requestedDestination, destination)
                    XCTAssertTrue(requestedState === state)
                    creationCount += 1
                    return window
                }
            )
            XCTAssertNil(controller.windowForTesting(destination))

            controller.show(destination, state: state)

            XCTAssertTrue(try XCTUnwrap(controller.windowForTesting(destination)) === window)
            XCTAssertEqual(window.identifier, destination.identifier)
            XCTAssertEqual(window.title, destination.title)
            XCTAssertEqual(window.level, .floating)
            XCTAssertTrue(window.collectionBehavior.contains(.moveToActiveSpace))
            XCTAssertTrue(window.collectionBehavior.contains(.fullScreenAuxiliary))
            XCTAssertEqual(creationCount, 1)
            XCTAssertEqual(activationCount, 1)

            window.focusRequests.removeAll()
            controller.show(destination, state: state)
            XCTAssertEqual(creationCount, 1)
            XCTAssertEqual(activationCount, 2)
        }
    }

    func testActivationRestoresRequestedWindowAfterShowingLyrics() {
        let state = DynasicAppState(
            userDefaults: UserDefaults(suiteName: "dynasic-windows-\(UUID().uuidString)")!
        )
        let window = FocusRecordingWindow(
            contentRect: NSRect(x: 100, y: 100, width: 360, height: 320),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        defer { window.close() }
        var activationCount = 0
        let controller = DynasicAuxiliaryWindowController(
            activateApplication: { _ in activationCount += 1 },
            windowFactory: { _, _ in window }
        )
        controller.show(.settings, state: state)
        window.focusRequests.removeAll()

        controller.restoreFocusAfterActivation()

        XCTAssertEqual(window.focusRequests, ["main", "key", "front"])
        XCTAssertEqual(activationCount, 1, "Restoring focus must not request another activation")

        controller.windowWillClose(Notification(name: NSWindow.willCloseNotification, object: window))
        window.focusRequests.removeAll()
        controller.restoreFocusAfterActivation()
        XCTAssertTrue(window.focusRequests.isEmpty, "A closed window must not be restored")
    }

    func testAuxiliaryControllerBuildsAndReusesBothHostedWindows() throws {
        let state = DynasicAppState(
            userDefaults: UserDefaults(suiteName: "dynasic-windows-\(UUID().uuidString)")!
        )
        let controller = DynasicAuxiliaryWindowController(activateApplication: { _ in })
        for destination in DynasicAuxiliaryWindow.allCases {
            XCTAssertNil(controller.windowForTesting(destination))
            controller.show(destination, state: state)
            let window = try XCTUnwrap(controller.windowForTesting(destination))
            defer { window.close() }
            let hostingView = try XCTUnwrap(window.contentView as? NSHostingView<AnyView>)
            XCTAssertTrue(hostingView.sizingOptions.isEmpty)
            XCTAssertTrue(window.isVisible)
            XCTAssertTrue(window.canBecomeMain)
            XCTAssertTrue(window.canBecomeKey)

            window.close()
            controller.show(destination, state: state)
            XCTAssertTrue(controller.windowForTesting(destination) === window)
            XCTAssertTrue(window.isVisible)
        }
    }

    func testActivationRequestsForegroundForTheCurrentAppWithoutLaunchingAnotherInstance() {
        var requestCount = 0
        var completionCount = 0
        DynasicApplicationActivation.request(completion: { completionCount += 1 }) { url, configuration, completion in
            requestCount += 1
            XCTAssertEqual(url, Bundle.main.bundleURL)
            XCTAssertTrue(configuration.activates)
            XCTAssertFalse(configuration.createsNewApplicationInstance)
            XCTAssertFalse(configuration.allowsRunningApplicationSubstitution)
            XCTAssertFalse(configuration.addsToRecentItems)
            completion()
        }
        XCTAssertEqual(requestCount, 1)
        XCTAssertEqual(completionCount, 1)
    }

    func testReopeningAuxiliaryWindowMovesItToTheInvokingScreen() throws {
        let state = DynasicAppState(
            userDefaults: UserDefaults(suiteName: "dynasic-windows-\(UUID().uuidString)")!
        )
        let recordedWindow = FocusRecordingWindow(
            contentRect: NSRect(x: 100, y: 100, width: 480, height: 580),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        recordedWindow.isReleasedWhenClosed = false
        var visibleFrame = NSRect(x: 0, y: 25, width: 1_440, height: 875)
        let controller = DynasicAuxiliaryWindowController(
            activateApplication: { _ in },
            windowFactory: { _, _ in recordedWindow },
            presentationVisibleFrame: { visibleFrame }
        )
        controller.show(.settings, state: state)
        let window = try XCTUnwrap(controller.windowForTesting(.settings))
        defer { window.close() }
        XCTAssertEqual(window.frame.midX, visibleFrame.midX, accuracy: 0.5)
        XCTAssertEqual(window.frame.midY, visibleFrame.midY, accuracy: 0.5)
        window.close()

        visibleFrame = NSRect(x: -1_920, y: 25, width: 1_920, height: 1_055)
        controller.show(.settings, state: state)

        XCTAssertTrue(controller.windowForTesting(.settings) === window)
        XCTAssertEqual(window.frame.midX, visibleFrame.midX, accuracy: 0.5)
        XCTAssertEqual(window.frame.midY, visibleFrame.midY, accuracy: 0.5)
        XCTAssertTrue(visibleFrame.contains(window.frame))
    }

    func testAuxiliaryWindowFitsScreensWithDifferentOriginsAndSizes() {
        let original = NSRect(x: 100, y: 100, width: 480, height: 580)
        for visible in [
            NSRect(x: -1_920, y: 25, width: 1_920, height: 1_055),
            NSRect(x: 1_440, y: -900, width: 1_600, height: 900),
            NSRect(x: 0, y: 0, width: 400, height: 300)
        ] {
            let centered = DynasicAuxiliaryWindowController.centeredFrame(for: original, in: visible)
            XCTAssertTrue(visible.contains(centered))
            XCTAssertEqual(centered.midX, visible.midX)
            XCTAssertEqual(centered.midY, visible.midY)
        }
    }

    func testActivationCompletionDoesNotFocusAClosedOrSupersededWindow() throws {
        let state = DynasicAppState(
            userDefaults: UserDefaults(suiteName: "dynasic-windows-\(UUID().uuidString)")!
        )
        var completions: [@MainActor () -> Void] = []
        let controller = DynasicAuxiliaryWindowController(
            activateApplication: { completions.append($0) },
            windowFactory: { _, _ in
                FocusRecordingWindow(
                    contentRect: NSRect(x: 100, y: 100, width: 360, height: 320),
                    styleMask: [.titled, .closable],
                    backing: .buffered,
                    defer: false
                )
            }
        )
        controller.show(.settings, state: state)
        let settings = try XCTUnwrap(controller.windowForTesting(.settings) as? FocusRecordingWindow)
        settings.focusRequests.removeAll()
        completions[0]()
        XCTAssertEqual(settings.focusRequests, ["main", "key", "front"])
        settings.focusRequests.removeAll()

        controller.show(.diagnostics, state: state)
        let diagnostics = try XCTUnwrap(controller.windowForTesting(.diagnostics) as? FocusRecordingWindow)
        diagnostics.focusRequests.removeAll()
        completions[0]()
        XCTAssertTrue(settings.focusRequests.isEmpty)
        completions[1]()
        XCTAssertEqual(diagnostics.focusRequests, ["main", "key", "front"])

        controller.windowWillClose(Notification(name: NSWindow.willCloseNotification, object: diagnostics))
        diagnostics.focusRequests.removeAll()
        completions[1]()
        XCTAssertTrue(diagnostics.focusRequests.isEmpty)
    }

    func testPanelPersistsAnchoredExpandedFrameAndRestoresItAfterCollapse() throws {
        let defaults = UserDefaults(suiteName: "dynasic-panel-\(UUID().uuidString)")!
        let controller = LyricsPanelController(
            state: DynasicAppState(userDefaults: defaults),
            userDefaults: defaults,
            positionKey: "frame",
            animationDuration: 0
        )

        controller.show()
        let panel = try XCTUnwrap(controller.panelForTesting)
        let requestedFrame = NSRect(x: 140, y: 180, width: 520, height: 240)
        panel.setFrame(requestedFrame, display: false)
        controller.finishUserMoveForTesting()
        let expectedFrame = panel.frame

        controller.toggleCollapsed()
        XCTAssertTrue(controller.isCollapsed)
        XCTAssertEqual(panel.frame.size, LyricsPanelController.collapsedSize)
        XCTAssertEqual(panel.minSize, LyricsPanelController.collapsedSize)
        XCTAssertEqual(panel.maxSize, LyricsPanelController.collapsedSize)
        XCTAssertFalse(panel.styleMask.contains(.resizable))
        XCTAssertFalse(panel.ignoresMouseEvents)

        controller.toggleCollapsed()
        XCTAssertFalse(controller.isCollapsed)
        XCTAssertTrue(panel.styleMask.contains(.resizable))
        XCTAssertTrue(panel.standardWindowButton(.closeButton)?.isHidden == true)
        XCTAssertTrue(panel.standardWindowButton(.miniaturizeButton)?.isHidden == true)
        XCTAssertTrue(panel.standardWindowButton(.zoomButton)?.isHidden == true)
        XCTAssertEqual(panel.minSize, LyricsPanelController.minimumExpandedSize)
        XCTAssertEqual(panel.maxSize, LyricsPanelController.maximumExpandedSize)
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
        XCTAssertFalse(panel.styleMask.contains(.resizable))
        XCTAssertEqual(panel.minSize, LyricsPanelController.collapsedSize)
        XCTAssertEqual(panel.maxSize, LyricsPanelController.collapsedSize)

        controller.toggleCollapsed()
        XCTAssertTrue(panel.ignoresMouseEvents)
        XCTAssertTrue(panel.styleMask.contains(.resizable))
    }

    func testCollapsedMouseDragMovesWithoutExpanding() throws {
        let defaults = UserDefaults(suiteName: "dynasic-panel-\(UUID().uuidString)")!
        let state = DynasicAppState(userDefaults: defaults)
        state.settings.isIconStickyToCorner = false
        let controller = LyricsPanelController(
            state: state,
            userDefaults: defaults,
            animationDuration: 0
        )

        controller.show()
        let panel = try XCTUnwrap(controller.panelForTesting)
        let expandedFrame = NSRect(x: 140, y: 180, width: 520, height: 240)
        panel.setFrame(expandedFrame, display: false)
        controller.finishUserMoveForTesting()
        let anchoredExpandedFrame = panel.frame
        controller.toggleCollapsed()
        let collapsedFrameOrigin = panel.frame.origin

        let startLocation = NSPoint(x: panel.frame.minX + 10, y: panel.frame.minY + 10)
        let endLocation = NSPoint(x: startLocation.x + 80, y: startLocation.y + 60)
        panel.sendEvent(mouseEvent(.leftMouseDown, at: startLocation, for: panel))
        panel.sendEvent(mouseEvent(.leftMouseDragged, at: endLocation, for: panel))
        panel.sendEvent(mouseEvent(.leftMouseUp, at: endLocation, for: panel))

        XCTAssertTrue(controller.isCollapsed)
        XCTAssertEqual(
            panel.frame.origin,
            NSPoint(
                x: collapsedFrameOrigin.x + 80,
                y: collapsedFrameOrigin.y + 60
            )
        )

        controller.toggleCollapsed()
        XCTAssertEqual(
            panel.frame,
            anchoredExpandedFrame.offsetBy(dx: 80, dy: 60)
        )
    }

    func testCollapsingPlacesIconAtNearestCorner() throws {
        let visible = NSRect(x: 100, y: 200, width: 1_000, height: 800)
        let frame = NSRect(x: 820, y: 760, width: 200, height: 100)

        XCTAssertEqual(
            LyricsPanelController.nearestCornerFrame(for: frame, in: visible),
            NSRect(x: 1_060, y: 960, width: 40, height: 40)
        )
    }

    func testCollapsedMouseDragSnapsToNearestCornerWhenEnabled() throws {
        let defaults = UserDefaults(suiteName: "dynasic-panel-\(UUID().uuidString)")!
        let state = DynasicAppState(userDefaults: defaults)
        let controller = LyricsPanelController(
            state: state,
            userDefaults: defaults,
            animationDuration: 0
        )

        controller.show()
        let panel = try XCTUnwrap(controller.panelForTesting)
        controller.toggleCollapsed()

        let visible = try XCTUnwrap(NSScreen.main).visibleFrame
        let draggedFrame = NSRect(
            x: visible.midX - LyricsPanelController.collapsedSize.width / 2,
            y: visible.midY - LyricsPanelController.collapsedSize.height / 2,
            width: LyricsPanelController.collapsedSize.width,
            height: LyricsPanelController.collapsedSize.height
        )
        panel.setFrame(draggedFrame, display: false)
        controller.finishUserMoveForTesting()

        XCTAssertEqual(
            panel.frame,
            LyricsPanelController.nearestCornerFrame(for: draggedFrame, in: visible)
        )
    }

    func testCollapsedSmallPointerMovementStillExpands() throws {
        let defaults = UserDefaults(suiteName: "dynasic-panel-\(UUID().uuidString)")!
        let controller = LyricsPanelController(
            state: DynasicAppState(userDefaults: defaults),
            userDefaults: defaults,
            animationDuration: 0
        )

        controller.show()
        let panel = try XCTUnwrap(controller.panelForTesting)
        controller.toggleCollapsed()
        let startLocation = NSPoint(x: panel.frame.minX + 10, y: panel.frame.minY + 10)
        let endLocation = NSPoint(x: startLocation.x + 2, y: startLocation.y + 2)

        panel.sendEvent(mouseEvent(.leftMouseDown, at: startLocation, for: panel))
        panel.sendEvent(mouseEvent(.leftMouseDragged, at: endLocation, for: panel))
        panel.sendEvent(mouseEvent(.leftMouseUp, at: endLocation, for: panel))

        XCTAssertFalse(controller.isCollapsed)
    }

    func testStickyToEdgeAnchorRunsOnlyWhenUserMoveFinishes() throws {
        let defaults = UserDefaults(suiteName: "dynasic-panel-\(UUID().uuidString)")!
        let state = DynasicAppState(userDefaults: defaults)
        let controller = LyricsPanelController(
            state: state,
            userDefaults: defaults,
            animationDuration: 0
        )

        controller.show()
        let panel = try XCTUnwrap(controller.panelForTesting)
        let screen = try XCTUnwrap(NSScreen.main)
        let visible = screen.visibleFrame
        let freeFrame = NSRect(
            x: visible.midX - 240,
            y: visible.maxY - 210,
            width: 480,
            height: 180
        )
        panel.setFrame(freeFrame, display: false)
        XCTAssertEqual(panel.frame.origin, freeFrame.origin)

        controller.finishUserMoveForTesting()
        XCTAssertEqual(panel.frame.midX, visible.midX, accuracy: 0.5)
        XCTAssertEqual(panel.frame.maxY, visible.maxY, accuracy: 0.5)
    }

    func testDisablingLyricsWindowStickyLeavesExpandedFrameFree() throws {
        let defaults = UserDefaults(suiteName: "dynasic-panel-\(UUID().uuidString)")!
        let state = DynasicAppState(userDefaults: defaults)
        state.settings.isLyricsWindowStickyToEdges = false
        let controller = LyricsPanelController(
            state: state,
            userDefaults: defaults,
            animationDuration: 0
        )

        controller.show()
        let panel = try XCTUnwrap(controller.panelForTesting)
        let freeFrame = NSRect(x: 240, y: 320, width: 480, height: 180)
        panel.setFrame(freeFrame, display: false)

        controller.finishUserMoveForTesting()

        XCTAssertEqual(panel.frame, freeFrame)
    }

    func testStickySnapStartsAfterMouseRelease() throws {
        let defaults = UserDefaults(suiteName: "dynasic-panel-\(UUID().uuidString)")!
        let state = DynasicAppState(userDefaults: defaults)
        let controller = LyricsPanelController(
            state: state,
            userDefaults: defaults,
            animationDuration: 0
        )

        controller.show()
        let panel = try XCTUnwrap(controller.panelForTesting)
        let visible = try XCTUnwrap(NSScreen.main).visibleFrame
        let startLocation = NSPoint(x: panel.frame.midX, y: panel.frame.midY)
        let freeFrame = NSRect(
            x: visible.midX - 200,
            y: visible.maxY - 190,
            width: 400,
            height: 160
        )
        panel.sendEvent(mouseEvent(.leftMouseDown, at: startLocation, for: panel))
        panel.setFrame(freeFrame, display: false)
        NotificationCenter.default.post(name: NSWindow.didMoveNotification, object: panel)
        XCTAssertEqual(panel.frame, freeFrame)

        panel.sendEvent(mouseEvent(.leftMouseUp, at: startLocation, for: panel))

        XCTAssertEqual(panel.frame.midX, visible.midX, accuracy: 0.5)
        XCTAssertEqual(panel.frame.maxY, visible.maxY, accuracy: 0.5)
    }

    func testEdgeAnchorFramesIncludeFourCornersAndFourEdgeMidpoints() {
        let visible = NSRect(x: 100, y: 200, width: 1_000, height: 800)
        let frame = NSRect(x: 0, y: 0, width: 200, height: 100)

        let anchors = LyricsPanelController.edgeAnchorFrames(for: frame, in: visible)

        XCTAssertEqual(
            anchors.map(\.origin),
            [
                NSPoint(x: 100, y: 200),
                NSPoint(x: 500, y: 200),
                NSPoint(x: 900, y: 200),
                NSPoint(x: 100, y: 500),
                NSPoint(x: 1_000, y: 500),
                NSPoint(x: 100, y: 900),
                NSPoint(x: 500, y: 900),
                NSPoint(x: 900, y: 900)
            ]
        )
        XCTAssertEqual(
            anchors.map(\.size),
            [
                NSSize(width: 200, height: 100),
                NSSize(width: 200, height: 100),
                NSSize(width: 200, height: 100),
                NSSize(width: 100, height: 200),
                NSSize(width: 100, height: 200),
                NSSize(width: 200, height: 100),
                NSSize(width: 200, height: 100),
                NSSize(width: 200, height: 100)
            ]
        )
    }

    func testEdgeMidpointsChooseOrientationAndCornersPreserveIt() throws {
        let defaults = UserDefaults(suiteName: "dynasic-panel-\(UUID().uuidString)")!
        let state = DynasicAppState(userDefaults: defaults)
        let controller = LyricsPanelController(
            state: state,
            userDefaults: defaults,
            animationDuration: 0
        )

        controller.show()
        let panel = try XCTUnwrap(controller.panelForTesting)
        let visible = try XCTUnwrap(NSScreen.main).visibleFrame
        let horizontalSize = panel.frame.size

        func movePanel(to origin: NSPoint) {
            panel.setFrameOrigin(origin)
            controller.finishUserMoveForTesting()
        }

        movePanel(
            to: NSPoint(
                x: visible.maxX - panel.frame.width,
                y: visible.midY - panel.frame.height / 2
            )
        )
        XCTAssertEqual(controller.contentOrientation, .vertical)
        XCTAssertEqual(
            panel.frame.size,
            NSSize(width: horizontalSize.height, height: horizontalSize.width)
        )
        XCTAssertEqual(
            panel.minSize,
            NSSize(
                width: LyricsPanelController.minimumExpandedSize.height,
                height: LyricsPanelController.minimumExpandedSize.width
            )
        )

        movePanel(
            to: NSPoint(
                x: visible.midX - panel.frame.width / 2,
                y: visible.maxY - panel.frame.height
            )
        )
        XCTAssertEqual(controller.contentOrientation, .horizontal)
        XCTAssertEqual(panel.frame.size, horizontalSize)

        movePanel(
            to: NSPoint(x: visible.minX, y: visible.midY - panel.frame.height / 2)
        )
        XCTAssertEqual(controller.contentOrientation, .vertical)
        let verticalSize = panel.frame.size

        movePanel(to: NSPoint(x: visible.minX, y: visible.maxY - panel.frame.height))
        XCTAssertEqual(controller.contentOrientation, .vertical)
        XCTAssertEqual(panel.frame.size, verticalSize)

        let restoredController = LyricsPanelController(
            state: state,
            userDefaults: defaults,
            animationDuration: 0
        )
        XCTAssertEqual(restoredController.contentOrientation, .vertical)
    }

    func testDisablingAutoRotatePreservesOrientationAndSize() throws {
        let defaults = UserDefaults(suiteName: "dynasic-panel-\(UUID().uuidString)")!
        let state = DynasicAppState(userDefaults: defaults)
        state.settings.isAutoRotateEnabled = false
        let controller = LyricsPanelController(
            state: state,
            userDefaults: defaults,
            animationDuration: 0
        )

        controller.show()
        let panel = try XCTUnwrap(controller.panelForTesting)
        let visible = try XCTUnwrap(NSScreen.main).visibleFrame
        let originalSize = panel.frame.size

        panel.setFrameOrigin(
            NSPoint(
                x: visible.maxX - panel.frame.width,
                y: visible.midY - panel.frame.height / 2
            )
        )
        controller.finishUserMoveForTesting()

        XCTAssertEqual(controller.contentOrientation, .horizontal)
        XCTAssertEqual(panel.frame.size, originalSize)
        XCTAssertEqual(panel.frame.maxX, visible.maxX, accuracy: 0.5)
        XCTAssertEqual(panel.frame.midY, visible.midY, accuracy: 0.5)
    }

    func testManualRotateSwapsSizeWhenAutoRotateIsDisabled() throws {
        let defaults = UserDefaults(suiteName: "dynasic-panel-\(UUID().uuidString)")!
        let state = DynasicAppState(userDefaults: defaults)
        state.settings.isAutoRotateEnabled = false
        let controller = LyricsPanelController(
            state: state,
            userDefaults: defaults,
            animationDuration: 0
        )

        controller.show()
        let panel = try XCTUnwrap(controller.panelForTesting)
        let visible = try XCTUnwrap(NSScreen.main).visibleFrame
        let horizontalFrame = NSRect(
            x: visible.midX - 260,
            y: visible.midY - 120,
            width: 520,
            height: 240
        )
        panel.setFrame(horizontalFrame, display: false)

        controller.rotateContent()

        XCTAssertEqual(controller.contentOrientation, .vertical)
        XCTAssertEqual(panel.frame.midX, horizontalFrame.midX, accuracy: 0.5)
        XCTAssertEqual(panel.frame.midY, horizontalFrame.midY, accuracy: 0.5)
        XCTAssertEqual(panel.frame.size, NSSize(width: 240, height: 520))

        controller.rotateContent()

        XCTAssertEqual(controller.contentOrientation, .horizontal)
        XCTAssertEqual(panel.frame.midX, horizontalFrame.midX, accuracy: 0.5)
        XCTAssertEqual(panel.frame.midY, horizontalFrame.midY, accuracy: 0.5)
        XCTAssertEqual(panel.frame.size, horizontalFrame.size)
    }

    func testLyricsPresentationIdentityChangesOncePerDisplayedLine() throws {
        let track = TrackMetadata(
            title: "Track",
            artist: "Artist",
            persistentID: "track-1"
        )
        let lyrics = Lyrics(lines: [
            LyricLine(timestamp: 0, text: "Previous"),
            LyricLine(timestamp: 10, text: "Current"),
            LyricLine(timestamp: 20, text: "Next")
        ])

        let current = try XCTUnwrap(
            LyricsLinePresentation(
                viewState: .displaying(track: track, lyrics: lyrics, currentIndex: 1)
            )
        )
        let unchanged = try XCTUnwrap(
            LyricsLinePresentation(
                viewState: .displaying(track: track, lyrics: lyrics, currentIndex: 1)
            )
        )
        let advanced = try XCTUnwrap(
            LyricsLinePresentation(
                viewState: .displaying(track: track, lyrics: lyrics, currentIndex: 2)
            )
        )
        let nextTrack = try XCTUnwrap(
            LyricsLinePresentation(
                viewState: .displaying(
                    track: TrackMetadata(
                        title: "Track 2",
                        artist: "Artist",
                        persistentID: "track-2"
                    ),
                    lyrics: lyrics,
                    currentIndex: 1
                )
            )
        )

        XCTAssertEqual(current.id, unchanged.id)
        XCTAssertNotEqual(current.id, advanced.id)
        XCTAssertNotEqual(current.id, nextTrack.id)
        XCTAssertEqual(current.lines.map(\.line.text), ["Previous", "Current", "Next"])

        let currentLines = current.lines
        let advancedLines = advanced.lines
        XCTAssertEqual(Set(currentLines.map(\.id)).count, currentLines.count)
        XCTAssertEqual(
            Set(currentLines.map(\.id)).intersection(Set(advancedLines.map(\.id))).count,
            2
        )
        XCTAssertEqual(currentLines.map(\.role), [.previous, .current, .next])
    }

    private func mouseEvent(
        _ type: NSEvent.EventType,
        at location: NSPoint,
        for panel: NSPanel
    ) -> NSEvent {
        NSEvent.mouseEvent(
            with: type,
            location: location,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: panel.windowNumber,
            context: nil,
            eventNumber: 1,
            clickCount: 1,
            pressure: 1
        )!
    }

    private final class FocusRecordingWindow: NSWindow {
        var focusRequests: [String] = []
        private var requestedFrame: NSRect?

        override var isVisible: Bool { true }
        override var frame: NSRect { requestedFrame ?? super.frame }

        override func setFrame(_ frameRect: NSRect, display flag: Bool) {
            requestedFrame = frameRect
        }

        override func makeMain() {
            focusRequests.append("main")
        }

        override func makeKeyAndOrderFront(_ sender: Any?) {
            focusRequests.append("key")
        }

        override func orderFrontRegardless() {
            focusRequests.append("front")
        }
    }
}
