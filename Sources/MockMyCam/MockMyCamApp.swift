import SwiftUI
import AppKit
import MockMyCamKit

@main
struct MockMyCamApp: App {
    @StateObject private var state = AppState()

    init() {
        // `_state` uses an autoclosure, so AppState() isn't built on this path.
        _state = StateObject(wrappedValue: AppState())
        if CommandLine.arguments.contains("--selftest") {
            SelfTest.run()
            exit(0)
        }
    }

    var body: some Scene {
        MenuBarExtra("MockMyCam", systemImage: "camera.viewfinder") {
            MenuContentView(state: state)
        }
        .menuBarExtraStyle(.window)
    }
}
