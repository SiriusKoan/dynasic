import AppKit
import SwiftUI

@main
struct DynasicApp: App {
    @StateObject private var appState: DynasicAppState

    init() {
        _appState = StateObject(wrappedValue: DynasicAppState(startImmediately: true))
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
