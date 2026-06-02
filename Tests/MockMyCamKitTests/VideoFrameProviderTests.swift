import XCTest
import AVFoundation
import CoreVideo
@testable import MockMyCamKit

final class VideoFrameProviderTests: XCTestCase {
    func testPlaysVideoAndEmitsFramesOfExpectedSize() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("vid-\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: url) }
        try makeSolidVideo(at: url, width: 320, height: 240, frames: 30)

        let provider = VideoFrameProvider(url: url)
        let expectation = expectation(description: "frame emitted")
        var received: BGRAFrame?
        provider.start { frame in
            if received == nil { received = frame; expectation.fulfill() }
        }
        wait(for: [expectation], timeout: 8.0)
        provider.stop()

        let frame = try XCTUnwrap(received)
        XCTAssertEqual(frame.width, 320)
        XCTAssertEqual(frame.height, 240)
        XCTAssertEqual(frame.data.count, 320 * 240 * 4)
    }

    // MARK: - Test video generation

    private func makeSolidVideo(at url: URL, width: Int, height: Int, frames: Int, fps: Int32 = 30) throws {
        try? FileManager.default.removeItem(at: url)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
            ])
        writer.add(input)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)

        for i in 0..<frames {
            while !input.isReadyForMoreMediaData { usleep(1_000) }
            let pixelBuffer = makeGreenPixelBuffer(width: width, height: height)
            adaptor.append(pixelBuffer, withPresentationTime: CMTime(value: CMTimeValue(i), timescale: fps))
        }
        input.markAsFinished()

        let done = DispatchSemaphore(value: 0)
        writer.finishWriting { done.signal() }
        done.wait()
        XCTAssertEqual(writer.status, .completed, "asset writer failed: \(String(describing: writer.error))")
    }

    private func makeGreenPixelBuffer(width: Int, height: Int) -> CVPixelBuffer {
        var pb: CVPixelBuffer?
        CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
        ] as CFDictionary, &pb)
        let buffer = pb!
        CVPixelBufferLockBaseAddress(buffer, [])
        let base = CVPixelBufferGetBaseAddress(buffer)!
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        for row in 0..<height {
            let rowPtr = base.advanced(by: row * stride).assumingMemoryBound(to: UInt8.self)
            for col in 0..<width {
                rowPtr[col * 4 + 0] = 0    // B
                rowPtr[col * 4 + 1] = 255  // G
                rowPtr[col * 4 + 2] = 0    // R
                rowPtr[col * 4 + 3] = 255  // A
            }
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        return buffer
    }
}
