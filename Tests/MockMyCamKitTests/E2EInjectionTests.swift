import XCTest
import AppKit
import CoreGraphics
@testable import MockMyCamKit

/// On-simulator end-to-end proofs. Gated behind MOCKMYCAM_E2E=1 (+ SIMPROBE_APP
/// and a booted sim) — run via `Scripts/e2e-smoke.sh`. Skipped in normal/CI runs.
final class E2EInjectionTests: XCTestCase {
    /// Solid green fills the preview → injection + writer + reader path works.
    func testGreenFrameAppearsInSimulatorPreview() throws {
        let (w, h) = (720, 1280)
        var px = [UInt8](repeating: 0, count: w * h * 4)
        for i in stride(from: 0, to: px.count, by: 4) { px[i + 1] = 255; px[i + 3] = 255 }
        let frame = BGRAFrame(data: Data(px), width: w, height: h)

        try runInjected(frame: frame, flags: .fillGravity, label: "green") { rep in
            let c = sampleColor(rep, fx: 0.5, fy: 0.5)
            XCTAssertGreaterThan(c.g, 0.5, "center not green — injection failed (\(c))")
            XCTAssertLessThan(c.r, 0.4, "center too red (\(c))")
            XCTAssertLessThan(c.b, 0.4, "center too blue (\(c))")
        }
    }

    /// Red top / blue bottom — proves orientation (row 0 == top) end to end
    /// through the real BGRAConverter, not just a symmetric solid color.
    func testImageOrientationInPreview() throws {
        let cg = try halfSplitCGImage(width: 600, height: 1200, top: (1, 0, 0), bottom: (0, 0, 1))
        let frame = try XCTUnwrap(BGRAConverter.frame(from: cg))

        try runInjected(frame: frame, flags: .fillGravity, label: "orientation") { rep in
            let top = sampleColor(rep, fx: 0.5, fy: 0.18)
            let bottom = sampleColor(rep, fx: 0.5, fy: 0.85)
            XCTAssertGreaterThan(top.r, 0.5, "top should be red (\(top))")
            XCTAssertLessThan(top.b, 0.4, "top should not be blue (\(top))")
            XCTAssertGreaterThan(bottom.b, 0.5, "bottom should be blue (\(bottom))")
            XCTAssertLessThan(bottom.r, 0.4, "bottom should not be red (\(bottom))")
        }
    }

    // MARK: - Helper

    private func runInjected(frame: BGRAFrame, flags: FrameLayout.Flags, label: String,
                             settle: TimeInterval = 3.0,
                             assert: (NSBitmapImageRep) throws -> Void) throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["MOCKMYCAM_E2E"] == "1",
            "Set MOCKMYCAM_E2E=1 and SIMPROBE_APP with a booted sim. See Scripts/e2e-smoke.sh.")
        let appPath = try XCTUnwrap(ProcessInfo.processInfo.environment["SIMPROBE_APP"], "SIMPROBE_APP not set")
        let dylibURL = try XCTUnwrap(BundledVirtualCamera.dylibURL, "VirtualCamera.dylib not bundled")

        let sim = SimulatorController()
        let device = try XCTUnwrap(try sim.bootedDevices().first, "No booted simulator found")
        let udid = device.udid
        let bundleID = "com.kaarlmoroti.SimProbe"

        let installedDylib = try DylibInstaller.install(dylibAt: dylibURL)
        try sim.install(appPath: appPath, udid: udid)

        // Feed continuously (>1fps) to beat the reader's 1s stale timeout.
        let writer = try SharedFrameWriter()
        let feedQueue = DispatchQueue(label: "mockmycam.e2e.feed")
        let timer = DispatchSource.makeTimerSource(queue: feedQueue)
        timer.schedule(deadline: .now(), repeating: 0.1)
        timer.setEventHandler {
            try? writer.write(bgra: frame.data, width: frame.width, height: frame.height, flags: flags)
        }
        timer.resume()
        defer { timer.cancel() }

        try sim.arm(udid: udid, dylibPath: installedDylib.path)
        defer { try? sim.disarm(udid: udid) }
        try? sim.terminate(bundleID: bundleID, udid: udid)
        try sim.launch(bundleID: bundleID, udid: udid)
        defer { try? sim.terminate(bundleID: bundleID, udid: udid) }

        Thread.sleep(forTimeInterval: settle)

        let shotPath = NSTemporaryDirectory() + "mockmycam-e2e-\(label)-\(UUID().uuidString).png"
        try sim.screenshot(to: shotPath, udid: udid)
        defer { try? FileManager.default.removeItem(atPath: shotPath) }
        if let dir = ProcessInfo.processInfo.environment["MOCKMYCAM_E2E_SHOT_DIR"] {
            let kept = dir + "/mockmycam-\(label).png"
            try? FileManager.default.removeItem(atPath: kept)
            try? FileManager.default.copyItem(atPath: shotPath, toPath: kept)
        }

        let rep = try XCTUnwrap(
            NSBitmapImageRep(data: Data(contentsOf: URL(fileURLWithPath: shotPath))),
            "could not decode screenshot PNG")
        try assert(rep)
    }
}
