import XCTest
@testable import MockMyCamKit

final class FrameLayoutTests: XCTestCase {
    func testTotalByteCountMatchesReader() {
        // Must equal kBufferSize in SimCamSharedFrameReader.m: 24 + 1280*1280*4.
        XCTAssertEqual(FrameLayout.totalByteCount, 24 + 1280 * 1280 * 4)
        XCTAssertEqual(FrameLayout.totalByteCount, 6_553_624)
    }

    func testHeaderOffsets() {
        XCTAssertEqual(FrameLayout.offsetSequence, 0)
        XCTAssertEqual(FrameLayout.offsetTimestampMs, 4)
        XCTAssertEqual(FrameLayout.offsetWidth, 8)
        XCTAssertEqual(FrameLayout.offsetHeight, 12)
        XCTAssertEqual(FrameLayout.offsetFlags, 16)
        XCTAssertEqual(FrameLayout.offsetReserved, 20)
        XCTAssertEqual(FrameLayout.headerSize, 24)
    }

    func testFlagBits() {
        XCTAssertEqual(FrameLayout.Flags.fillGravity.rawValue, 1)
        XCTAssertEqual(FrameLayout.Flags.mirror.rawValue, 2)
    }
}
