import Foundation
import MockMyCamKit

/// Headless sanity check used by `make app` / CI to confirm the packaged bundle
/// can locate its dylib resource and reach `simctl`. Run:
///   MockMyCam.app/Contents/MacOS/MockMyCam --selftest
enum SelfTest {
    static func run() {
        print("MockMyCam self-test")
        print("  bundlePath:  \(Bundle.main.bundlePath)")
        print("  bundleURL:   \(Bundle.main.bundleURL.path)")
        print("  resourceURL: \(Bundle.main.resourceURL?.path ?? "nil")")
        if let url = BundledVirtualCamera.dylibURL {
            print("  ✓ dylib bundled: \(url.path)")
        } else {
            print("  ✗ dylib MISSING from bundle")
        }
        let booted = (try? SimulatorController().bootedDevices()) ?? []
        print("  booted simulators: \(booted.count)")
        for device in booted { print("    - \(device.name) [\(device.udid)]") }
    }
}
