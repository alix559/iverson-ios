/// App entry point for iverson.io.

import SwiftUI

@main
struct IversonApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        #if os(macOS)
        .defaultSize(width: 780, height: 920)
        .windowStyle(.hiddenTitleBar)
        #endif
    }
}
