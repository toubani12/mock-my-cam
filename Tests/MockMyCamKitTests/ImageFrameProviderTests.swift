import XCTest
@testable import MockMyCamKit

final class ImageFrameProviderTests: XCTestCase {
    func testLoadsImageFileAndEmitsFrame() throws {
        // Write a 10x10 red PNG, load it, expect a BGRA-red 10x10 frame.
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("img-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }
        try writePNG(try solidCGImage(width: 10, height: 10, r: 1, g: 0, b: 0), to: url)

        let provider = try XCTUnwrap(ImageFrameProvider(url: url, fps: 30))
        let expectation = expectation(description: "frame emitted")
        var received: BGRAFrame?
        provider.start { frame in
            if received == nil { received = frame; expectation.fulfill() }
        }
        wait(for: [expectation], timeout: 2.0)
        provider.stop()

        let frame = try XCTUnwrap(received)
        XCTAssertEqual(frame.width, 10)
        XCTAssertEqual(frame.height, 10)
        XCTAssertEqual(frame.data.count, 10 * 10 * 4)
        let bytes = [UInt8](frame.data)
        XCTAssertEqual(bytes[2], 255, "R channel of red pixel")
    }

    func testReturnsNilForBadFile() {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("not-an-image-\(UUID().uuidString).png")
        try? Data("garbage".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertNil(ImageFrameProvider(url: url))
    }
}
