import Foundation
import CoreGraphics
import ImageIO

/// Emits a single still image repeatedly. The repeat (default 10fps) keeps the
/// reader from showing its "no signal" placeholder, which kicks in after 1s of
/// no new frame.
public final class ImageFrameProvider: FrameProvider {
    private let frame: BGRAFrame
    private let interval: TimeInterval
    private var timer: DispatchSourceTimer?

    public init(frame: BGRAFrame, fps: Double = 10) {
        self.frame = frame
        self.interval = 1.0 / max(1, fps)
    }

    /// Loads + converts an image file. Returns nil if it can't be decoded.
    public convenience init?(url: URL, maxDimension: Int = FrameLayout.maxCanvas, fps: Double = 10) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let frame = BGRAConverter.frame(from: cgImage, maxDimension: maxDimension) else {
            return nil
        }
        self.init(frame: frame, fps: fps)
    }

    public func start(_ onFrame: @escaping (BGRAFrame) -> Void) {
        let frame = self.frame
        onFrame(frame)  // emit immediately
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "mockmycam.image"))
        timer.schedule(deadline: .now() + interval, repeating: interval)
        timer.setEventHandler { onFrame(frame) }
        timer.resume()
        self.timer = timer
    }

    public func stop() {
        timer?.cancel()
        timer = nil
    }
}
