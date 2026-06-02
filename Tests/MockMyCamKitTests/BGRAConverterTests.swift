import XCTest
import CoreGraphics
@testable import MockMyCamKit

final class BGRAConverterTests: XCTestCase {
    func testChannelOrderIsBGRA() throws {
        // Pure red in -> every output pixel must be B=0, G=0, R=255, A=255.
        let red = try solidCGImage(width: 4, height: 4, r: 1, g: 0, b: 0)
        let frame = try XCTUnwrap(BGRAConverter.frame(from: red))
        XCTAssertEqual(frame.width, 4)
        XCTAssertEqual(frame.height, 4)
        XCTAssertEqual(frame.data.count, 4 * 4 * 4)

        let bytes = [UInt8](frame.data)
        for pixel in stride(from: 0, to: bytes.count, by: 4) {
            XCTAssertEqual(bytes[pixel + 0], 0, "B")
            XCTAssertEqual(bytes[pixel + 1], 0, "G")
            XCTAssertEqual(bytes[pixel + 2], 255, "R")
            XCTAssertEqual(bytes[pixel + 3], 255, "A")
        }
    }

    func testScalesDownPreservingAspect() throws {
        let big = try solidCGImage(width: 2000, height: 1000, r: 0, g: 1, b: 0)
        let frame = try XCTUnwrap(BGRAConverter.frame(from: big))
        XCTAssertEqual(frame.width, 1280)
        XCTAssertEqual(frame.height, 640)
        XCTAssertEqual(frame.data.count, 1280 * 640 * 4)
    }

    func testSmallImageNotUpscaled() throws {
        let small = try solidCGImage(width: 100, height: 50, r: 0, g: 0, b: 1)
        let frame = try XCTUnwrap(BGRAConverter.frame(from: small))
        XCTAssertEqual(frame.width, 100)
        XCTAssertEqual(frame.height, 50)
    }

    func testFittedSize() {
        XCTAssertEqual(BGRAConverter.fittedSize(width: 1920, height: 1080).width, 1280)
        XCTAssertEqual(BGRAConverter.fittedSize(width: 1920, height: 1080).height, 720)
        XCTAssertEqual(BGRAConverter.fittedSize(width: 640, height: 480).width, 640)
        XCTAssertEqual(BGRAConverter.fittedSize(width: 2560, height: 2560).width, 1280)
    }
}
