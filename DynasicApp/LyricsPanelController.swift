import AppKit
import SwiftUI

@MainActor
final class LyricsPanelController {
    private let state: DynasicAppState
    private let userDefaults: UserDefaults
    private let positionKey: String
    private var panel: NSPanel?
    private var moveObserver: NSObjectProtocol?

    init(
        state: DynasicAppState,
        userDefaults: UserDefaults = .standard,
        positionKey: String = "dynasic.lyricsPanel.origin"
    ) {
        self.state = state
        self.userDefaults = userDefaults
        self.positionKey = positionKey
    }

    deinit {
        if let moveObserver {
            NotificationCenter.default.removeObserver(moveObserver)
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
        panel?.ignoresMouseEvents = enabled
    }

    var isVisible: Bool {
        panel?.isVisible == true
    }

    var panelForTesting: NSPanel? { panel }

    private func makePanelIfNeeded() -> NSPanel {
        if let panel { return panel }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 150),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: LyricsPanelView(state: state))

        if let origin = savedOrigin() {
            panel.setFrameOrigin(origin)
        } else {
            panel.center()
        }

        self.panel = panel
        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: panel,
            queue: .main
        ) { [weak self] notification in
            guard let window = notification.object as? NSWindow else { return }
            Task { @MainActor [weak self] in
                self?.saveOrigin(window.frame.origin)
            }
        }
        return panel
    }

    private func savedOrigin() -> NSPoint? {
        guard let values = userDefaults.array(forKey: positionKey) as? [Double],
              values.count == 2 else {
            return nil
        }
        return NSPoint(x: values[0], y: values[1])
    }

    private func saveOrigin(_ origin: NSPoint) {
        userDefaults.set([origin.x, origin.y], forKey: positionKey)
    }
}
