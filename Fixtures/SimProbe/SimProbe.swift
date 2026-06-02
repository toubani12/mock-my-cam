// SimProbe — a minimal iOS app used to verify camera injection.
//
// It puts an AVCaptureVideoPreviewLayer on screen and assigns it a session,
// which triggers the injected dylib's swizzled `-[AVCaptureVideoPreviewLayer
// setSession:]` hook. With injection working, the layer shows MockMyCam's frames;
// without it, the magenta background shows through (an obvious failure signal).
import UIKit
import AVFoundation

final class ViewController: UIViewController {
    private let previewLayer = AVCaptureVideoPreviewLayer()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .magenta
        let session = AVCaptureSession()
        previewLayer.session = session            // triggers the swizzled setSession:
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer.frame = view.bounds
    }
}

final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = ViewController()
        window.makeKeyAndVisible()
        self.window = window
        return true
    }
}

UIApplicationMain(CommandLine.argc, CommandLine.unsafeArgv, nil, NSStringFromClass(AppDelegate.self))
