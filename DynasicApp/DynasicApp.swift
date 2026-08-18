import AppKit
import SwiftUI

final class DynasicAppDelegate: NSObject, NSApplicationDelegate {
    var onReopen: (() -> Void)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        showMainWindowOnNextRunLoop()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        showMainWindowOnNextRunLoop()
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        showMainWindowOnNextRunLoop()
        return true
    }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        showMainWindowOnNextRunLoop()
        return true
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        showMainWindowOnNextRunLoop()
        sender.reply(toOpenOrPrint: .success)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        showMainWindowOnNextRunLoop()
    }

    private func showMainWindowOnNextRunLoop() {
        DispatchQueue.main.async { [weak self] in
            self?.onReopen?()
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
        appDelegate.onReopen = { [weak state] in
            state?.showMainWindow()
        }
    }

    var body: some Scene {
        MenuBarExtra("dynasic", systemImage: "music.note") {
            MenuBarView(state: appState)
        }

        Window("Settings", id: "settings") {
            SettingsView(state: appState)
        }

        Window("Diagnostics", id: "diagnostics") {
            DiagnosticsView(state: appState)
        }
    }
}
