import SwiftUI

import AppKit

@main
struct DynasicApp: App {
    @StateObject private var appState = DynasicAppState()

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
