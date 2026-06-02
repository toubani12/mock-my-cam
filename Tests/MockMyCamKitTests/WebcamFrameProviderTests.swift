import XCTest
import AVFoundation
@testable import MockMyCamKit

/// Live webcam capture test. Gated behind MOCKMYCAM_WEBCAM=1 because it needs a
/// real camera + granted TCC permission for the test runner. Run manually:
///   MOCKMYCAM_WEBCAM=1 swift test --filter WebcamFrameProviderTests
final class WebcamFrameProviderTests: XCTestCase {
    func testCapturesFramesFromDefaultCamera() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["MOCKMYCAM_WEBCAM"] == "1",
                          "Set MOCKMYCAM_WEBCAM=1 with camera access granted to run.")
        try XCTSkipUnless(CameraAuthorization.status == .authorized,
                          "Camera not authorized for the test runner.")
        try XCTSkipUnless(!WebcamFrameProvider.availableCameras().isEmpty, "No camera found.")

        let provider = WebcamFrameProvider()
        let expectation = expectation(description: "frame captured")
        var received: BGRAFrame?
        provider.start { frame in
            if received == nil { received = frame; expectation.fulfill() }
        }
        wait(for: [expectation], timeout: 10.0)
        provider.stop()

        let frame = try XCTUnwrap(received)
        XCTAssertGreaterThan(frame.width, 0)
        XCTAssertGreaterThan(frame.height, 0)
        XCTAssertLessThanOrEqual(frame.width, FrameLayout.maxCanvas)
        XCTAssertEqual(frame.data.count, frame.width * frame.height * 4)
    }
}
