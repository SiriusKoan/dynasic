import AppKit
import SwiftUI

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
            self?.onShowLyrics?()
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
        }

        Window("Diagnostics", id: "diagnostics") {
            DiagnosticsView(state: appState)
        }
    }
}
