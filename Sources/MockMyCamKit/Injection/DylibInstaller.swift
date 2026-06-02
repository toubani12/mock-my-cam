import Foundation
import CryptoKit

/// Installs `VirtualCamera.dylib` to a content-addressed path so iOS 26's dyld
/// page-hash cache never sees the same path with different bytes (which it
/// rejects). The dylib is copied verbatim — it must NOT be re-codesigned, since
/// the simulator's dyld accepts the linker's adhoc signature but rejects a
/// post-build `codesign --force` one.
public enum DylibInstaller {
    /// First 12 hex chars of the SHA-256 of the dylib bytes.
    public static func sha12(of data: Data) -> String {
        let digest = SHA256.hash(data: data)
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return String(hex.prefix(12))
    }

    public static func appSupportRoot(appName: String = "MockMyCam") throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true)
        return base.appendingPathComponent(appName, isDirectory: true)
    }

    public static func installDir(root: URL, sha12: String) -> URL {
        root.appendingPathComponent("builds", isDirectory: true)
            .appendingPathComponent(sha12, isDirectory: true)
    }

    /// Copies the dylib into `~/Library/Application Support/<appName>/builds/<sha12>/`
    /// and returns the destination path. Idempotent.
    @discardableResult
    public static func install(dylibAt source: URL, appName: String = "MockMyCam") throws -> URL {
        let data = try Data(contentsOf: source)
        let sha = sha12(of: data)
        let dir = installDir(root: try appSupportRoot(appName: appName), sha12: sha)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let dest = dir.appendingPathComponent("VirtualCamera.dylib")
        if !FileManager.default.fileExists(atPath: dest.path) {
            try data.write(to: dest)
        }
        // Executable bit; deliberately no codesign step.
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dest.path)
        return dest
    }
}
