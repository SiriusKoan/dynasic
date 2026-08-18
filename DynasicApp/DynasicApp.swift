import AppKit
import SwiftUI

@main
struct DynasicApp: App {
    var body: some Scene {
        MenuBarExtra("dynasic", systemImage: "music.note") {
            Text("dynasic")
                .font(.headline)

            Divider()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}
