import SwiftUI
import AppKit

@main
struct OvitalMapApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                // Disable "New"
            }
        }
    }
}
