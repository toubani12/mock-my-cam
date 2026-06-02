import XCTest
@testable import MockMyCamKit

final class SharedFrameWriterTests: XCTestCase {
    private func tempPath() -> String {
        NSTemporaryDirectory() + "SimCamTest-\(UUID().uuidString).bgra"
    }

    private func readU32LE(_ data: Data, at offset: Int) -> UInt32 {
        data.withUnsafeBytes { raw in
            var v: UInt32 = 0
            memcpy(&v, raw.baseAddress!.advanced(by: offset), 4)
            return UInt32(littleEndian: v)
        }
    }

    func testWritesHeaderAndPixelsWithExactLayout() throws {
        let path = tempPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let writer = try SharedFrameWriter(path: path)

        let width = 4, height = 3
        // Distinct per-pixel bytes so a misaligned write would be caught.
        let pixels = Data((0..<(width * height * 4)).map { UInt8($0 % 256) })

        let seq = try writer.write(bgra: pixels, width: width, height: height, flags: [.mirror])
        XCTAssertEqual(seq, 1, "first published frame must be sequence 1, not 0")

        let file = try Data(contentsOf: URL(fileURLWithPath: path))
        XCTAssertEqual(file.count, FrameLayout.totalByteCount)
        XCTAssertEqual(readU32LE(file, at: FrameLayout.offsetSequence), 1)
        XCTAssertEqual(readU32LE(file, at: FrameLayout.offsetWidth), 4)
        XCTAssertEqual(readU32LE(file, at: FrameLayout.offsetHeight), 3)
        XCTAssertEqual(readU32LE(file, at: FrameLayout.offsetFlags), FrameLayout.Flags.mirror.rawValue)
        XCTAssertEqual(readU32LE(file, at: FrameLayout.offsetReserved), 0)

        let pixelRegion = file.subdata(in: FrameLayout.headerSize ..< (FrameLayout.headerSize + pixels.count))
        XCTAssertEqual(pixelRegion, pixels, "pixels must be tightly packed at offset 24")
    }

    func testSequenceIncrementsPerWrite() throws {
        let path = tempPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let writer = try SharedFrameWriter(path: path)
        let pixels = Data(repeating: 0, count: 2 * 2 * 4)

        XCTAssertEqual(try writer.write(bgra: pixels, width: 2, height: 2), 1)
        XCTAssertEqual(try writer.write(bgra: pixels, width: 2, height: 2), 2)
        XCTAssertEqual(try writer.write(bgra: pixels, width: 2, height: 2), 3)
    }

    func testRejectsPixelCountMismatch() throws {
        let path = tempPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let writer = try SharedFrameWriter(path: path)
        XCTAssertThrowsError(try writer.write(bgra: Data(repeating: 0, count: 10), width: 4, height: 3)) {
            XCTAssertEqual($0 as? SharedFrameWriterError, .pixelCountMismatch(expected: 48, got: 10))
        }
    }

    func testRejectsOversizeDimensions() throws {
        let path = tempPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let writer = try SharedFrameWriter(path: path)
        let bad = 1281
        XCTAssertThrowsError(try writer.write(bgra: Data(repeating: 0, count: bad * 1 * 4),
                                              width: bad, height: 1)) {
            XCTAssertEqual($0 as? SharedFrameWriterError, .invalidDimensions(width: bad, height: 1))
        }
    }
}
