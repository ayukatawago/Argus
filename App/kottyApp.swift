import SwiftUI

@main
struct KottyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .defaultSize(width: 1200, height: 800)
        .windowStyle(.titleBar)
    }
}
