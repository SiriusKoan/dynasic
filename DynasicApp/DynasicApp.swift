import AppKit
import SwiftUI

@MainActor
enum DynasicAuxiliaryWindow: String, CaseIterable {
    case settings
    case diagnostics

    var identifier: NSUserInterfaceItemIdentifier {
        NSUserInterfaceItemIdentifier("dynasic.\(rawValue)")
    }

    var title: String {
        self == .settings ? "Settings" : "Diagnostics"
    }
}

@MainActor
private final class DynasicUtilityWindow: NSWindow {
    override var canBecomeMain: Bool { true }
    override var canBecomeKey: Bool { true }
}

@MainActor
enum DynasicApplicationActivation {
    static func request(
        completion: @escaping @MainActor () -> Void,
        openApplication: (URL, NSWorkspace.OpenConfiguration, @escaping @MainActor () -> Void) -> Void = { url, configuration, completion in
            NSWorkspace.shared.openApplication(
                at: url,
                configuration: configuration,
                completionHandler: { _, error in
                    if let error {
                        NSLog("dynasic activation failed: %@", error.localizedDescription)
                        return
                    }
                    DispatchQueue.main.async { completion() }
                }
            )
        }
    ) {
        // NSWorkspace supplies activation context for clicks on the nonactivating overlay.
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.createsNewApplicationInstance = false
        configuration.allowsRunningApplicationSubstitution = false
        configuration.addsToRecentItems = false
        openApplication(Bundle.main.bundleURL, configuration, completion)
    }
}

@MainActor
final class DynasicAuxiliaryWindowController: NSObject, NSWindowDelegate {
    private var windows: [DynasicAuxiliaryWindow: NSWindow] = [:]
    private weak var presentedWindow: NSWindow?
    private let activateApplication: @MainActor (@escaping @MainActor () -> Void) -> Void
    private let windowFactory: (DynasicAuxiliaryWindow, DynasicAppState) -> NSWindow
    private let presentationVisibleFrame: @MainActor () -> NSRect?

    init(
        activateApplication: @escaping @MainActor (@escaping @MainActor () -> Void) -> Void = { completion in
            DynasicApplicationActivation.request(completion: completion)
        },
        windowFactory: ((DynasicAuxiliaryWindow, DynasicAppState) -> NSWindow)? = nil,
        presentationVisibleFrame: @escaping @MainActor () -> NSRect? = {
            let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
            return (screen ?? NSScreen.main)?.visibleFrame
        }
    ) {
        self.activateApplication = activateApplication
        self.windowFactory = windowFactory ?? Self.makeWindow
        self.presentationVisibleFrame = presentationVisibleFrame
        super.init()
    }

    func show(_ destination: DynasicAuxiliaryWindow, state: DynasicAppState) {
        let window: NSWindow
        if let existing = windows[destination] {
            window = existing
        } else {
            window = windowFactory(destination, state)
            window.identifier = destination.identifier
            window.title = destination.title
            window.isReleasedWhenClosed = false
            window.level = .floating
            window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            window.delegate = self
            windows[destination] = window
        }
        presentedWindow = window
        if let visibleFrame = presentationVisibleFrame() {
            window.setFrame(Self.centeredFrame(for: window.frame, in: visibleFrame), display: false)
        }
        // Select the actual window before asking macOS to activate the app.
        bringForward(window)
        activateApplication { [weak self, weak window] in
            guard let self, let window,
                  self.presentedWindow === window, window.isVisible else { return }
            self.bringForward(window)
        }
    }

    func restoreFocusAfterActivation() {
        guard let window = presentedWindow, window.isVisible else { return }
        bringForward(window)
    }

    func windowWillClose(_ notification: Notification) {
        if notification.object as? NSWindow === presentedWindow {
            presentedWindow = nil
        }
    }

    func windowForTesting(_ destination: DynasicAuxiliaryWindow) -> NSWindow? {
        windows[destination]
    }

    static func centeredFrame(for frame: NSRect, in visibleFrame: NSRect) -> NSRect {
        let size = NSSize(
            width: min(frame.width, visibleFrame.width),
            height: min(frame.height, visibleFrame.height)
        )
        return NSRect(
            x: visibleFrame.midX - size.width / 2,
            y: visibleFrame.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    private func bringForward(_ window: NSWindow) {
        window.makeMain()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    private static func makeWindow(
        _ destination: DynasicAuxiliaryWindow,
        state: DynasicAppState
    ) -> NSWindow {
        let content: AnyView
        let size: NSSize
        switch destination {
        case .settings:
            content = AnyView(SettingsView(state: state))
            size = NSSize(width: 480, height: 560)
        case .diagnostics:
            content = AnyView(DiagnosticsView(state: state))
            size = NSSize(width: 480, height: 320)
        }
        let window = DynasicUtilityWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        let hostingView = NSHostingView(rootView: content)
        hostingView.sizingOptions = []
        window.contentView = hostingView
        window.setContentSize(size)
        window.center()
        return window
    }
}

@MainActor
final class DynasicAppDelegate: NSObject, NSApplicationDelegate {
    var onShowLyrics: (() -> Void)?
    var onRestoreAuxiliaryFocus: (() -> Void)?
    var onTerminationRequest: (() async -> Void)?
    private var terminationTask: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        showLyricsOnNextRunLoop()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        showLyricsOnNextRunLoop()
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        showLyricsOnNextRunLoop()
        return true
    }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        showLyricsOnNextRunLoop()
        return true
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        showLyricsOnNextRunLoop()
        sender.reply(toOpenOrPrint: .success)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        showLyricsOnNextRunLoop()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let onTerminationRequest else { return .terminateNow }
        guard terminationTask == nil else { return .terminateLater }

        terminationTask = Task { @MainActor in
            await onTerminationRequest()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    private func showLyricsOnNextRunLoop() {
        DispatchQueue.main.async { [weak self] in
            self?.onShowLyrics?()
            self?.onRestoreAuxiliaryFocus?()
        }
    }
}

@main
struct DynasicApp: App {
    @NSApplicationDelegateAdaptor(DynasicAppDelegate.self) private var appDelegate
    @StateObject private var appState: DynasicAppState

    init() {
        let state = DynasicAppState(startImmediately: true)
        _appState = StateObject(wrappedValue: state)
        appDelegate.onShowLyrics = { [weak state] in
            state?.showLyrics()
        }
        appDelegate.onRestoreAuxiliaryFocus = { [weak state] in
            state?.restoreAuxiliaryWindowFocus()
        }
        appDelegate.onTerminationRequest = { [weak state] in
            await state?.shutdown()
        }
    }

    var body: some Scene {
        MenuBarExtra("dynasic", systemImage: "music.note") {
            MenuBarView(state: appState)
        }
    }
}
