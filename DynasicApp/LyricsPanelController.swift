import AppKit
import Combine
import SwiftUI

enum LyricsPanelContentOrientation: String, Equatable {
    case horizontal
    case vertical
}

@MainActor
private final class LyricsPanelWindow: NSPanel {
    private static let collapsedDragThreshold: CGFloat = 4

    var onUserFinishedMoving: (() -> Void)?
    var onUserTapped: (() -> Void)?

    var isCollapsedForInteraction = false

    private var collapsedPointerDownLocation: NSPoint?
    private var collapsedPointerDownOrigin: NSPoint?
    private var didMoveCollapsedPanel = false
    private var expandedPointerDownOrigin: NSPoint?

    override func sendEvent(_ event: NSEvent) {
        guard isCollapsedForInteraction else {
            if event.type == .leftMouseDown {
                expandedPointerDownOrigin = frame.origin
            }
            super.sendEvent(event)
            if event.type == .leftMouseDown || event.type == .leftMouseUp,
               let expandedPointerDownOrigin,
               expandedPointerDownOrigin != frame.origin {
                self.expandedPointerDownOrigin = nil
                onUserFinishedMoving?()
            } else if event.type == .leftMouseUp {
                expandedPointerDownOrigin = nil
            }
            return
        }

        if event.type == .leftMouseDown {
            collapsedPointerDownLocation = convertPoint(toScreen: event.locationInWindow)
            collapsedPointerDownOrigin = frame.origin
            didMoveCollapsedPanel = false
        }

        switch event.type {
        case .leftMouseDragged:
            guard let collapsedPointerDownLocation,
                  let collapsedPointerDownOrigin else { return }
            let currentLocation = convertPoint(toScreen: event.locationInWindow)
            let delta = NSPoint(
                x: currentLocation.x - collapsedPointerDownLocation.x,
                y: currentLocation.y - collapsedPointerDownLocation.y
            )
            guard hypot(delta.x, delta.y) >= Self.collapsedDragThreshold else { return }
            setFrameOrigin(
                NSPoint(
                    x: collapsedPointerDownOrigin.x + delta.x,
                    y: collapsedPointerDownOrigin.y + delta.y
                )
            )
            didMoveCollapsedPanel = true
            return
        case .leftMouseUp:
            var didMove = didMoveCollapsedPanel
            if !didMove,
               let collapsedPointerDownLocation,
               let collapsedPointerDownOrigin {
                let currentLocation = convertPoint(toScreen: event.locationInWindow)
                let delta = NSPoint(
                    x: currentLocation.x - collapsedPointerDownLocation.x,
                    y: currentLocation.y - collapsedPointerDownLocation.y
                )
                if hypot(delta.x, delta.y) >= Self.collapsedDragThreshold {
                    setFrameOrigin(
                        NSPoint(
                            x: collapsedPointerDownOrigin.x + delta.x,
                            y: collapsedPointerDownOrigin.y + delta.y
                        )
                    )
                    didMove = true
                }
            }
            collapsedPointerDownLocation = nil
            collapsedPointerDownOrigin = nil
            didMoveCollapsedPanel = false
            if didMove {
                onUserFinishedMoving?()
            } else {
                onUserTapped?()
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
    private struct EdgeAnchorTarget {
        let frame: NSRect
        let orientation: LyricsPanelContentOrientation?
    }

    private enum FrameMutationState: Equatable {
        case idle
        case applying
        case animating
    }

    static let minimumExpandedSize = NSSize(width: 420, height: 120)
    static let maximumExpandedSize = NSSize(width: 10_000, height: 360)
    static let collapsedSize = NSSize(width: 40, height: 40)
    private static let unconstrainedExpandedSize = NSSize(width: 10_000, height: 10_000)

    private let state: DynasicAppState
    private let userDefaults: UserDefaults
    private let frameKey: String
    private let legacyOriginKey: String
    private let orientationKey: String
    private let animationDuration: TimeInterval
    private var panel: LyricsPanelWindow?
    private var moveObserver: NSObjectProtocol?
    private var resizeObserver: NSObjectProtocol?
    private var moveEndMonitor: Any?
    private var frameMutationState = FrameMutationState.idle
    private var expandedFrame: NSRect?
    private var collapsedFrameOrigin: NSPoint?

    @Published private(set) var isCollapsed = false
    @Published private(set) var contentOrientation: LyricsPanelContentOrientation

    init(
        state: DynasicAppState,
        userDefaults: UserDefaults = .standard,
        positionKey: String = "dynasic.lyricsPanel.frame",
        legacyOriginKey: String = "dynasic.lyricsPanel.origin",
        animationDuration: TimeInterval = 0.22
    ) {
        let orientationKey = "\(positionKey).contentOrientation"
        self.state = state
        self.userDefaults = userDefaults
        self.frameKey = positionKey
        self.legacyOriginKey = legacyOriginKey
        self.orientationKey = orientationKey
        self.animationDuration = max(0, animationDuration)
        self.contentOrientation = LyricsPanelContentOrientation(
            rawValue: userDefaults.string(forKey: orientationKey) ?? ""
        ) ?? .horizontal
    }

    deinit {
        if let moveObserver {
            NotificationCenter.default.removeObserver(moveObserver)
        }
        if let resizeObserver {
            NotificationCenter.default.removeObserver(resizeObserver)
        }
        if let moveEndMonitor {
            NSEvent.removeMonitor(moveEndMonitor)
        }
    }

    func show() {
        let panel = makePanelIfNeeded()
        panel.orderFrontRegardless()
        state.refreshWaveformCapture()
        guard !isCollapsed, frameMutationState != .animating else { return }

        let visibleFrame = frameConstrainedToVisibleScreen(panel.frame)
        applyFrame(visibleFrame, to: panel)
        expandedFrame = visibleFrame
        saveFrame(visibleFrame)
    }

    func hide() {
        panel?.orderOut(nil)
        state.refreshWaveformCapture()
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

    var frameDescription: String {
        guard let frame = panel?.frame else { return "not created" }
        return String(
            format: "x=%.0f y=%.0f width=%.0f height=%.0f",
            frame.origin.x,
            frame.origin.y,
            frame.width,
            frame.height
        )
    }

    func toggleCollapsed() {
        guard frameMutationState != .animating else { return }
        if isCollapsed {
            expand()
        } else {
            collapse()
        }
    }

    func rotateContent() {
        guard let panel, !isCollapsed, frameMutationState == .idle else { return }

        let frame = panel.frame
        panel.minSize = NSSize(width: 1, height: 1)
        panel.maxSize = Self.unconstrainedExpandedSize
        setContentOrientation(contentOrientation == .horizontal ? .vertical : .horizontal)
        let target = frameConstrainedToVisibleScreen(
            NSRect(
                x: frame.midX - frame.height / 2,
                y: frame.midY - frame.width / 2,
                width: frame.height,
                height: frame.width
            )
        )
        animateFrame(target, on: panel) { [weak self, weak panel] in
            guard let self, let panel else { return }
            self.applyExpandedSizeLimits(to: panel)
            self.recordFinishedFrame(panel.frame)
        }
    }

    func finishUserMoveForTesting() {
        finishUserMove()
    }

    private func makePanelIfNeeded() -> LyricsPanelWindow {
        if let panel { return panel }

        let panel = LyricsPanelWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 260),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.title = ""
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.titlebarSeparatorStyle = .none
        hideStandardWindowButtons(on: panel)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovable = true
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
        panel.onUserTapped = { [weak self] in
            self?.toggleCollapsed()
        }
        self.panel = panel
        let hostingView = NSHostingView(rootView: LyricsPanelView(state: state, controller: self))
        hostingView.sizingOptions = []
        panel.contentView = hostingView
        applyExpandedSizeLimits(to: panel)

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
                self?.monitorUserMoveEnd()
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
        let limits = expandedSizeLimits
        return NSRect(
            x: values[0],
            y: values[1],
            width: min(max(values[2], limits.minimum.width), limits.maximum.width),
            height: min(max(values[3], limits.minimum.height), limits.maximum.height)
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
        guard frameMutationState == .idle else { return }
        if isCollapsed {
            recordCollapsedFrameChange(window.frame)
            return
        }
        expandedFrame = window.frame
        saveFrame(window.frame)
    }

    private func recordCollapsedFrameChange(_ frame: NSRect) {
        guard let collapsedFrameOrigin,
              let expandedFrame else { return }

        let delta = NSPoint(
            x: frame.origin.x - collapsedFrameOrigin.x,
            y: frame.origin.y - collapsedFrameOrigin.y
        )
        guard delta != .zero else { return }

        let movedExpandedFrame = expandedFrame.offsetBy(dx: delta.x, dy: delta.y)
        self.expandedFrame = movedExpandedFrame
        self.collapsedFrameOrigin = frame.origin
        saveFrame(movedExpandedFrame)
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
        state.refreshWaveformCapture()
        panel.isCollapsedForInteraction = true
        panel.isMovableByWindowBackground = false
        panel.styleMask.remove(.resizable)
        hideStandardWindowButtons(on: panel)
        panel.minSize = NSSize(width: 1, height: 1)
        let collapsedFrame = NSRect(
            x: panel.frame.minX,
            y: panel.frame.maxY - Self.collapsedSize.height,
            width: Self.collapsedSize.width,
            height: Self.collapsedSize.height
        )
        collapsedFrameOrigin = collapsedFrame.origin
        panel.ignoresMouseEvents = false
        animateFrame(collapsedFrame, on: panel) { [weak panel] in
            guard let panel else { return }
            panel.minSize = Self.collapsedSize
            panel.maxSize = Self.collapsedSize
        }
    }

    private func expand() {
        guard let panel, isCollapsed else { return }

        let frame = frameConstrainedToVisibleScreen(expandedFrame ?? panel.frame)
        isCollapsed = false
        state.refreshWaveformCapture()
        collapsedFrameOrigin = nil
        panel.isCollapsedForInteraction = false
        panel.isMovableByWindowBackground = true
        panel.styleMask.insert(.resizable)
        hideStandardWindowButtons(on: panel)
        panel.minSize = NSSize(width: 1, height: 1)
        panel.maxSize = Self.unconstrainedExpandedSize
        panel.ignoresMouseEvents = state.settings.isClickThrough
        animateFrame(frame, on: panel) { [weak self, weak panel] in
            guard let self, let panel else { return }
            self.applyExpandedSizeLimits(to: panel)
            self.hideStandardWindowButtons(on: panel)
            self.expandedFrame = panel.frame
            self.saveFrame(panel.frame)
        }
    }

    private func hideStandardWindowButtons(on panel: NSWindow) {
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
    }

    private func applyFrame(_ frame: NSRect, to panel: NSWindow) {
        frameMutationState = .applying
        panel.setFrame(frame, display: false, animate: false)
        frameMutationState = .idle
    }

    private func animateFrame(
        _ frame: NSRect,
        on panel: NSWindow,
        duration: TimeInterval? = nil,
        completion: @escaping @MainActor () -> Void
    ) {
        let duration = duration ?? animationDuration
        frameMutationState = .animating
        guard duration > 0 else {
            panel.setFrame(frame, display: false, animate: false)
            frameMutationState = .idle
            completion()
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(frame, display: true)
        } completionHandler: {
            MainActor.assumeIsolated {
                self.frameMutationState = .idle
                completion()
            }
        }
    }

    private func finishUserMove() {
        guard let panel, frameMutationState == .idle else { return }
        stopMonitoringUserMoveEnd()

        guard state.settings.isStickyToCorner else {
            recordFinishedFrame(panel.frame)
            return
        }

        let target = nearestEdgeAnchorTarget(for: panel.frame)
        let changesOrientation = target.orientation.map { $0 != contentOrientation } == true
        if changesOrientation {
            panel.minSize = NSSize(width: 1, height: 1)
            panel.maxSize = Self.unconstrainedExpandedSize
        }
        if let orientation = target.orientation {
            setContentOrientation(orientation)
        }
        guard target.frame != panel.frame else {
            applyExpandedSizeLimits(to: panel)
            recordFinishedFrame(panel.frame)
            return
        }

        animateFrame(
            target.frame,
            on: panel,
            duration: animationDuration * 2.25
        ) { [weak self, weak panel] in
            guard let self, let panel else { return }
            self.applyExpandedSizeLimits(to: panel)
            self.recordFinishedFrame(panel.frame)
        }
    }

    private func monitorUserMoveEnd() {
        guard !isCollapsed,
              state.settings.isStickyToCorner,
              frameMutationState == .idle,
              moveEndMonitor == nil else { return }

        moveEndMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) {
            [weak self] event in
            MainActor.assumeIsolated {
                self?.finishUserMove()
            }
            return event
        }
    }

    private func stopMonitoringUserMoveEnd() {
        guard let moveEndMonitor else { return }
        NSEvent.removeMonitor(moveEndMonitor)
        self.moveEndMonitor = nil
    }

    private func recordFinishedFrame(_ frame: NSRect) {
        if isCollapsed {
            recordCollapsedFrameChange(frame)
        } else {
            expandedFrame = frame
            saveFrame(frame)
        }
    }

    private func setContentOrientation(_ orientation: LyricsPanelContentOrientation) {
        contentOrientation = orientation
        userDefaults.set(orientation.rawValue, forKey: orientationKey)
    }

    private func nearestEdgeAnchorTarget(for frame: NSRect) -> EdgeAnchorTarget {
        let candidates = NSScreen.screens.flatMap { screen in
            Self.edgeAnchorTargets(
                for: frame,
                in: screen.visibleFrame,
                currentOrientation: contentOrientation,
                autoRotates: state.settings.isAutoRotateEnabled
            )
        }

        guard let nearest = candidates.min(by: {
            distanceSquared(from: frame.center, to: $0.frame.center)
                < distanceSquared(from: frame.center, to: $1.frame.center)
        }) else {
            return EdgeAnchorTarget(frame: frame, orientation: nil)
        }
        return nearest
    }

    static func edgeAnchorFrames(
        for frame: NSRect,
        in visibleFrame: NSRect,
        currentOrientation: LyricsPanelContentOrientation = .horizontal
    ) -> [NSRect] {
        edgeAnchorTargets(
            for: frame,
            in: visibleFrame,
            currentOrientation: currentOrientation,
            autoRotates: true
        ).map(\.frame)
    }

    private static func edgeAnchorTargets(
        for frame: NSRect,
        in visibleFrame: NSRect,
        currentOrientation: LyricsPanelContentOrientation,
        autoRotates: Bool
    ) -> [EdgeAnchorTarget] {
        func target(
            _ horizontalPosition: CGFloat,
            _ verticalPosition: CGFloat,
            _ orientation: LyricsPanelContentOrientation? = nil
        ) -> EdgeAnchorTarget {
            let orientation = autoRotates ? orientation : nil
            var size = frame.size
            if let orientation, orientation != currentOrientation {
                size = NSSize(width: size.height, height: size.width)
            }
            size.width = min(size.width, visibleFrame.width)
            size.height = min(size.height, visibleFrame.height)
            return EdgeAnchorTarget(
                frame: NSRect(
                    x: visibleFrame.minX
                        + (visibleFrame.width - size.width) * horizontalPosition,
                    y: visibleFrame.minY
                        + (visibleFrame.height - size.height) * verticalPosition,
                    width: size.width,
                    height: size.height
                ),
                orientation: orientation
            )
        }

        return [
            target(0, 0),
            target(0.5, 0, .horizontal),
            target(1, 0),
            target(0, 0.5, .vertical),
            target(1, 0.5, .vertical),
            target(0, 1),
            target(0.5, 1, .horizontal),
            target(1, 1)
        ]
    }

    private var expandedSizeLimits: (minimum: NSSize, maximum: NSSize) {
        switch contentOrientation {
        case .horizontal:
            return (Self.minimumExpandedSize, Self.maximumExpandedSize)
        case .vertical:
            return (
                NSSize(
                    width: Self.minimumExpandedSize.height,
                    height: Self.minimumExpandedSize.width
                ),
                NSSize(
                    width: Self.maximumExpandedSize.height,
                    height: Self.maximumExpandedSize.width
                )
            )
        }
    }

    private func applyExpandedSizeLimits(to panel: NSWindow) {
        let limits = expandedSizeLimits
        panel.minSize = limits.minimum
        panel.maxSize = limits.maximum
    }

    private func frameConstrainedToVisibleScreen(_ frame: NSRect) -> NSRect {
        guard let screen = screenBestMatching(frame) else { return frame }

        let visible = screen.visibleFrame
        let limits = expandedSizeLimits
        let width = min(
            max(frame.width, limits.minimum.width),
            limits.maximum.width,
            visible.width
        )
        let height = min(
            max(frame.height, limits.minimum.height),
            limits.maximum.height,
            visible.height
        )
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
