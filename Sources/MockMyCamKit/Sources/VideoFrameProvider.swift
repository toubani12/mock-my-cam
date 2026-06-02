import AVFoundation
import CoreVideo

/// Plays a video file on a loop and emits its frames as BGRA at ~30fps.
public final class VideoFrameProvider: FrameProvider {
    private let url: URL
    private let maxDimension: Int
    private let player = AVPlayer()
    private var videoOutput: AVPlayerItemVideoOutput?
    private var timer: DispatchSourceTimer?
    private var endObserver: NSObjectProtocol?
    private var onFrame: ((BGRAFrame) -> Void)?

    public init(url: URL, maxDimension: Int = FrameLayout.maxCanvas) {
        self.url = url
        self.maxDimension = maxDimension
    }

    public func start(_ onFrame: @escaping (BGRAFrame) -> Void) {
        self.onFrame = onFrame

        let item = AVPlayerItem(url: url)
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ])
        item.add(output)
        videoOutput = output

        player.replaceCurrentItem(with: item)
        player.actionAtItemEnd = .none
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak player] _ in
            player?.seek(to: .zero)
            player?.play()
        }
        player.play()

        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "mockmycam.video"))
        timer.schedule(deadline: .now(), repeating: 1.0 / 30.0)
        timer.setEventHandler { [weak self] in self?.pull() }
        timer.resume()
        self.timer = timer
    }

    private func pull() {
        guard let output = videoOutput else { return }
        let time = player.currentTime()
        guard output.hasNewPixelBuffer(forItemTime: time) else { return }
        var display = CMTime.zero
        guard let pixelBuffer = output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: &display) else { return }
        if let frame = BGRAConverter.frame(from: pixelBuffer, maxDimension: maxDimension) {
            onFrame?(frame)
        }
    }

    public func stop() {
        timer?.cancel()
        timer = nil
        player.pause()
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        onFrame = nil
    }
}
