import AVFoundation

/// Thin wrapper over the macOS camera (TCC) authorization for the Mac webcam.
public enum CameraAuthorization {
    public static var status: AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .video)
    }

    public static func request(_ completion: @escaping (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .video, completionHandler: completion)
    }
}
