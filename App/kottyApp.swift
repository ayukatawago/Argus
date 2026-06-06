import SwiftUI

@main
struct KottyApp: App {
    @StateObject private var ghosttyApp = GhosttyApp()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(ghosttyApp)
        }
        .defaultSize(width: 1200, height: 800)
        .windowStyle(.titleBar)
    }
}
