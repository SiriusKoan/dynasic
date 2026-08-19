import AppKit
import Combine
import SwiftUI

@MainActor
private final class LyricsPanelWindow: NSPanel {
    var onUserFinishedMoving: (() -> Void)?

    private var pointerIsDown = false
    private var movedDuringPointer = false
    private var resizedDuringPointer = false
    private var pointerDownOrigin: NSPoint?

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            pointerIsDown = true
            movedDuringPointer = false
            resizedDuringPointer = false
            pointerDownOrigin = frame.origin
        case .leftMouseDragged:
            let wasLiveResizing = inLiveResize
            super.sendEvent(event)
            resizedDuringPointer = resizedDuringPointer || wasLiveResizing || inLiveResize
            if let pointerDownOrigin, frame.origin != pointerDownOrigin {
                movedDuringPointer = true
            }
            return
        case .leftMouseUp:
            let didFinishMoving = pointerIsDown && movedDuringPointer && !resizedDuringPointer
            pointerIsDown = false
            movedDuringPointer = false
            resizedDuringPointer = false
            pointerDownOrigin = nil
            super.sendEvent(event)
            if didFinishMoving {
                onUserFinishedMoving?()
            }
            return
        default:
            break
        }

        super.sendEvent(event)
    }
}

@MainActor
final class LyricsPanelController: ObservableObject {
    static let minimumExpandedSize = NSSize(width: 420, height: 220)
    static let collapsedSize = NSSize(width: 56, height: 56)

    private let state: DynasicAppState
    private let userDefaults: UserDefaults
    private let frameKey: String
    private let legacyOriginKey: String
    private var panel: LyricsPanelWindow?
    private var moveObserver: NSObjectProtocol?
    private var resizeObserver: NSObjectProtocol?
    private var isApplyingFrame = false
    private var expandedFrame: NSRect?
    private var expandedMaximumSize: NSSize?

    @Published private(set) var isCollapsed = false

    init(
        state: DynasicAppState,
        userDefaults: UserDefaults = .standard,
        positionKey: String = "dynasic.lyricsPanel.frame",
        legacyOriginKey: String = "dynasic.lyricsPanel.origin"
    ) {
        self.state = state
        self.userDefaults = userDefaults
        self.frameKey = positionKey
        self.legacyOriginKey = legacyOriginKey
    }

    deinit {
        if let moveObserver {
            NotificationCenter.default.removeObserver(moveObserver)
        }
        if let resizeObserver {
            NotificationCenter.default.removeObserver(resizeObserver)
        }
    }

    func show() {
        let panel = makePanelIfNeeded()
        panel.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    func setClickThrough(_ enabled: Bool) {
        panel?.ignoresMouseEvents = isCollapsed ? false : enabled
    }

    func setAlwaysOnTop(_ enabled: Bool) {
        panel?.isFloatingPanel = enabled
        panel?.level = enabled ? .floating : .normal
    }

    var isVisible: Bool {
        panel?.isVisible == true
    }

    var panelForTesting: NSPanel? { panel }

    func toggleCollapsed() {
        if isCollapsed {
            expand()
        } else {
            collapse()
        }
    }

    func finishUserMoveForTesting() {
        finishUserMove()
    }

    private func makePanelIfNeeded() -> LyricsPanelWindow {
        if let panel { return panel }

        let panel = LyricsPanelWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 260),
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.minSize = Self.minimumExpandedSize
        expandedMaximumSize = panel.maxSize
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isFloatingPanel = true
        panel.level = state.settings.isAlwaysOnTop ? .floating : .normal
        panel.ignoresMouseEvents = state.settings.isClickThrough
        panel.isFloatingPanel = state.settings.isAlwaysOnTop
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.onUserFinishedMoving = { [weak self] in
            self?.finishUserMove()
        }
        self.panel = panel
        panel.contentView = NSHostingView(rootView: LyricsPanelView(state: state, controller: self))

        if let frame = savedFrame() {
            let visibleFrame = frameConstrainedToVisibleScreen(frame)
            expandedFrame = visibleFrame
            applyFrame(visibleFrame, to: panel)
        } else if let origin = savedLegacyOrigin() {
            let frame = frameConstrainedToVisibleScreen(
                NSRect(origin: origin, size: panel.frame.size)
            )
            expandedFrame = frame
            applyFrame(frame, to: panel)
        } else {
            panel.center()
            expandedFrame = panel.frame
        }

        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: panel,
            queue: .main
        ) { [weak self] notification in
            guard let window = notification.object as? NSWindow else { return }
            MainActor.assumeIsolated {
                self?.recordFrameChange(window)
            }
        }
        resizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification,
            object: panel,
            queue: .main
        ) { [weak self] notification in
            guard let window = notification.object as? NSWindow else { return }
            MainActor.assumeIsolated {
                self?.recordFrameChange(window)
            }
        }
        return panel
    }

    private func savedFrame() -> NSRect? {
        guard let values = userDefaults.array(forKey: frameKey) as? [Double],
              values.count == 4,
              values.allSatisfy(\.isFinite) else {
            return nil
        }
        return NSRect(
            x: values[0],
            y: values[1],
            width: max(values[2], Self.minimumExpandedSize.width),
            height: max(values[3], Self.minimumExpandedSize.height)
        )
    }

    private func savedLegacyOrigin() -> NSPoint? {
        guard let values = userDefaults.array(forKey: legacyOriginKey) as? [Double],
              values.count == 2,
              values.allSatisfy(\.isFinite) else {
            return nil
        }
        return NSPoint(x: values[0], y: values[1])
    }

    private func recordFrameChange(_ window: NSWindow) {
        guard !isCollapsed, !isApplyingFrame else { return }
        expandedFrame = window.frame
        saveFrame(window.frame)
    }

    private func saveFrame(_ frame: NSRect) {
        userDefaults.set(
            [frame.origin.x, frame.origin.y, frame.size.width, frame.size.height],
            forKey: frameKey
        )
    }

    private func collapse() {
        guard let panel, !isCollapsed else { return }

        expandedFrame = panel.frame
        saveFrame(panel.frame)
        isCollapsed = true
        panel.minSize = Self.collapsedSize
        panel.maxSize = Self.collapsedSize
        let collapsedFrame = NSRect(
            x: panel.frame.minX,
            y: panel.frame.maxY - Self.collapsedSize.height,
            width: Self.collapsedSize.width,
            height: Self.collapsedSize.height
        )
        applyFrame(collapsedFrame, to: panel)
        panel.ignoresMouseEvents = false
    }

    private func expand() {
        guard let panel, isCollapsed else { return }

        let frame = frameConstrainedToVisibleScreen(expandedFrame ?? panel.frame)
        isCollapsed = false
        if let expandedMaximumSize {
            panel.maxSize = expandedMaximumSize
        }
        panel.minSize = Self.minimumExpandedSize
        applyFrame(frame, to: panel)
        expandedFrame = panel.frame
        saveFrame(panel.frame)
        panel.ignoresMouseEvents = state.settings.isClickThrough
    }

    private func applyFrame(_ frame: NSRect, to panel: NSWindow) {
        isApplyingFrame = true
        panel.setFrame(frame, display: false, animate: false)
        isApplyingFrame = false
    }

    private func finishUserMove() {
        guard let panel else { return }

        if state.settings.isStickyToCorner {
            applyFrame(nearestCornerFrame(for: panel.frame), to: panel)
        }

        if !isCollapsed {
            expandedFrame = panel.frame
            saveFrame(panel.frame)
        }
    }

    private func nearestCornerFrame(for frame: NSRect) -> NSRect {
        let candidates = NSScreen.screens.flatMap { screen -> [NSRect] in
            let visible = screen.visibleFrame
            let width = min(frame.width, visible.width)
            let height = min(frame.height, visible.height)
            let maxX = visible.maxX - width
            let maxY = visible.maxY - height
            return [
                NSRect(x: visible.minX, y: visible.minY, width: width, height: height),
                NSRect(x: maxX, y: visible.minY, width: width, height: height),
                NSRect(x: visible.minX, y: maxY, width: width, height: height),
                NSRect(x: maxX, y: maxY, width: width, height: height)
            ]
        }

        guard let nearest = candidates.min(by: { distanceSquared(from: frame.origin, to: $0.origin) < distanceSquared(from: frame.origin, to: $1.origin) }) else {
            return frame
        }
        return nearest
    }

    private func frameConstrainedToVisibleScreen(_ frame: NSRect) -> NSRect {
        guard let screen = screenBestMatching(frame) else { return frame }

        let visible = screen.visibleFrame
        let width = min(max(frame.width, Self.minimumExpandedSize.width), visible.width)
        let height = min(max(frame.height, Self.minimumExpandedSize.height), visible.height)
        let x = min(max(frame.minX, visible.minX), visible.maxX - width)
        let y = min(max(frame.minY, visible.minY), visible.maxY - height)
        return NSRect(x: x, y: y, width: width, height: height)
    }

    private func screenBestMatching(_ frame: NSRect) -> NSScreen? {
        let intersectingScreen = NSScreen.screens.max { lhs, rhs in
            lhs.visibleFrame.intersection(frame).area < rhs.visibleFrame.intersection(frame).area
        }
        if let intersectingScreen,
           intersectingScreen.visibleFrame.intersects(frame) {
            return intersectingScreen
        }

        let center = NSPoint(x: frame.midX, y: frame.midY)
        return NSScreen.screens.min { lhs, rhs in
            distanceSquared(from: center, to: lhs.visibleFrame.center)
                < distanceSquared(from: center, to: rhs.visibleFrame.center)
        }
    }

    private func distanceSquared(from lhs: NSPoint, to rhs: NSPoint) -> CGFloat {
        let dx = lhs.x - rhs.x
        let dy = lhs.y - rhs.y
        return dx * dx + dy * dy
    }
}

private extension NSRect {
    var area: CGFloat {
        width * height
    }

    var center: NSPoint {
        NSPoint(x: midX, y: midY)
    }
}
