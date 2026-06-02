import Foundation

/// Locates the `VirtualCamera.dylib` that ships inside the app bundle.
///
/// The dylib is the iOS-Simulator injection library (vendored from baguette /
/// SimCam, Apache-2.0 — see `ThirdParty/VirtualCamera/`). It is built by
/// `Scripts/build-dylib.sh` into `Sources/MockMyCamKit/Resources/` and copied
/// into the resource bundle, so `Bundle.module` resolves it both during
/// `swift run`/tests and inside the packaged `.app`.
public enum BundledVirtualCamera {
    /// URL of the bundled `VirtualCamera.dylib`, or `nil` if it wasn't built
    /// (run `make dylib` / `Scripts/build-dylib.sh`).
    public static var dylibURL: URL? {
        // Packaged .app: the dylib ships flat in Contents/Resources (codesign-
        // friendly — nothing at the bundle root). Checked first so the packaged
        // app never reaches Bundle.module's build-path fallback (which would
        // fatalError on a machine without a .build directory).
        if let url = Bundle.main.url(forResource: "VirtualCamera", withExtension: "dylib") {
            return url
        }
        // swift run / swift test: resolve via the SwiftPM resource bundle.
        return Bundle.module.url(forResource: "VirtualCamera", withExtension: "dylib")
    }
}
