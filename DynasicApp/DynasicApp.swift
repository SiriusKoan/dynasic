import AppKit
import SwiftUI

@MainActor
enum DynasicAuxiliaryWindow: String, CaseIterable {
    case settings
    case diagnostics

    private static weak var pendingFocusWindow: NSWindow?

    var identifier: NSUserInterfaceItemIdentifier {
        NSUserInterfaceItemIdentifier("dynasic.\(rawValue)")
    }

    func open(using openWindow: OpenWindowAction) {
        NSApplication.shared.activate(ignoringOtherApps: true)
        openWindow(id: rawValue)
        if let window = NSApplication.shared.windows.first(where: { $0.identifier == identifier }) {
            focus(window)
        }
    }

    func focus(
        _ window: NSWindow,
        activateApplication: () -> Void = {
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    ) {
        window.identifier = identifier
        // Keep utility windows above the floating lyrics overlay.
        window.level = .floating
        Self.pendingFocusWindow = NSApplication.shared.isActive ? nil : window
        activateApplication()
        window.makeKeyAndOrderFront(nil)
    }

    static func finishPendingActivation() {
        guard NSApplication.shared.isActive, let window = pendingFocusWindow else { return }
        pendingFocusWindow = nil
        guard window.isVisible else { return }
        window.makeKeyAndOrderFront(nil)
    }
}

private struct AuxiliaryWindowFocus: NSViewRepresentable {
    let destination: DynasicAuxiliaryWindow

    func makeNSView(context: Context) -> FocusView {
        let view = FocusView()
        view.destination = destination
        return view
    }

    func updateNSView(_ nsView: FocusView, context: Context) {}

    final class FocusView: NSView {
        var destination: DynasicAuxiliaryWindow?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window, let destination else { return }
            window.identifier = destination.identifier
            DispatchQueue.main.async { [weak self, weak window] in
                guard let self, let window, self.window === window else { return }
                destination.focus(window)
            }
        }
    }
}

@MainActor
final class DynasicAppDelegate: NSObject, NSApplicationDelegate {
    var onShowLyrics: (() -> Void)?
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
            let keyWindow = NSApplication.shared.keyWindow
            self?.onShowLyrics?()
            if let keyWindow,
               DynasicAuxiliaryWindow.allCases.contains(where: { $0.identifier == keyWindow.identifier }) {
                keyWindow.orderFrontRegardless()
            }
            DynasicAuxiliaryWindow.finishPendingActivation()
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
        appDelegate.onTerminationRequest = { [weak state] in
            await state?.shutdown()
        }
    }

    var body: some Scene {
        MenuBarExtra("dynasic", systemImage: "music.note") {
            MenuBarView(state: appState)
        }

        Window("Settings", id: "settings") {
            SettingsView(state: appState)
                .background(AuxiliaryWindowFocus(destination: .settings))
        }

        Window("Diagnostics", id: "diagnostics") {
            DiagnosticsView(state: appState)
                .background(AuxiliaryWindowFocus(destination: .diagnostics))
        }
    }
}
