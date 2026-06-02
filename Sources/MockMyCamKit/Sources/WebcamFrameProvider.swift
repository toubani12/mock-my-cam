import AVFoundation
import CoreVideo

/// Streams the Mac's webcam as BGRA frames via an `AVCaptureSession`.
public final class WebcamFrameProvider: NSObject, FrameProvider,
                                        AVCaptureVideoDataOutputSampleBufferDelegate {
    private let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "mockmycam.webcam")
    private var onFrame: ((BGRAFrame) -> Void)?
    private let deviceID: String?
    private let maxDimension: Int

    /// `deviceID` is an `AVCaptureDevice.uniqueID`; nil picks the system default.
    public init(deviceID: String? = nil, maxDimension: Int = FrameLayout.maxCanvas) {
        self.deviceID = deviceID
        self.maxDimension = maxDimension
        super.init()
    }

    /// All cameras the Mac can see (built-in, external/USB, Continuity, Desk View).
    public static func availableCameras() -> [AVCaptureDevice] {
        let types: [AVCaptureDevice.DeviceType] = [
            .builtInWideAngleCamera, .external, .continuityCamera, .deskViewCamera,
        ]
        return AVCaptureDevice.DiscoverySession(
            deviceTypes: types, mediaType: .video, position: .unspecified).devices
    }

    public func start(_ onFrame: @escaping (BGRAFrame) -> Void) {
        self.onFrame = onFrame
        queue.async { [weak self] in self?.configureAndRun() }
    }

    private func configureAndRun() {
        guard !session.isRunning else { return }
        session.beginConfiguration()
        if session.canSetSessionPreset(.hd1280x720) {
            session.sessionPreset = .hd1280x720
        }

        let device = deviceID.flatMap { AVCaptureDevice(uniqueID: $0) }
            ?? AVCaptureDevice.default(for: .video)
        guard let device,
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            session.commitConfiguration()
            return
        }
        session.addInput(input)

        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)
        if session.canAddOutput(output) { session.addOutput(output) }

        session.commitConfiguration()
        session.startRunning()
    }

    public func stop() {
        onFrame = nil
        queue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    public func captureOutput(_ output: AVCaptureOutput,
                              didOutput sampleBuffer: CMSampleBuffer,
                              from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
              let frame = BGRAConverter.frame(from: pixelBuffer, maxDimension: maxDimension) else { return }
        onFrame?(frame)
    }
}
