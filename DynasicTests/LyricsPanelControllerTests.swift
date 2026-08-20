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
        let state = DynasicAppState()
        let controller = LyricsPanelController(state: state)

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
        let controller = LyricsPanelController(
            state: DynasicAppState(userDefaults: defaults),
            userDefaults: defaults,
            animationDuration: 0
        )

        controller.show()
        let panel = try XCTUnwrap(controller.panelForTesting)
        let expandedFrame = NSRect(x: 140, y: 180, width: 520, height: 240)
        panel.setFrame(expandedFrame, display: false)
        controller.finishUserMoveForTesting()
        controller.toggleCollapsed()

        let startLocation = NSPoint(x: panel.frame.minX + 10, y: panel.frame.minY + 10)
        let endLocation = NSPoint(x: startLocation.x + 80, y: startLocation.y + 60)
        panel.sendEvent(mouseEvent(.leftMouseDown, at: startLocation, for: panel))
        panel.sendEvent(mouseEvent(.leftMouseDragged, at: endLocation, for: panel))
        panel.sendEvent(mouseEvent(.leftMouseUp, at: endLocation, for: panel))

        XCTAssertTrue(controller.isCollapsed)
        XCTAssertEqual(
            panel.frame.origin,
            NSPoint(
                x: expandedFrame.minX + 80,
                y: expandedFrame.maxY - LyricsPanelController.collapsedSize.height + 60
            )
        )

        controller.toggleCollapsed()
        XCTAssertEqual(
            panel.frame,
            expandedFrame.offsetBy(dx: 80, dy: 60)
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
        state.settings.isStickyToCorner = true
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

    func testStickySnapStartsAfterMouseRelease() throws {
        let defaults = UserDefaults(suiteName: "dynasic-panel-\(UUID().uuidString)")!
        let state = DynasicAppState(userDefaults: defaults)
        state.settings.isStickyToCorner = true
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

        let origins = LyricsPanelController.edgeAnchorFrames(for: frame, in: visible)
            .map(\.origin)

        XCTAssertEqual(
            origins,
            [
                NSPoint(x: 100, y: 200),
                NSPoint(x: 500, y: 200),
                NSPoint(x: 900, y: 200),
                NSPoint(x: 100, y: 550),
                NSPoint(x: 900, y: 550),
                NSPoint(x: 100, y: 900),
                NSPoint(x: 500, y: 900),
                NSPoint(x: 900, y: 900)
            ]
        )
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

        let currentLines = current.visibleLines(showsPrevious: true, showsNext: true)
        let advancedLines = advanced.visibleLines(showsPrevious: true, showsNext: true)
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
}
