import XCTest
@testable import MockMyCamKit

final class DylibInstallerTests: XCTestCase {
    func testSha12MatchesKnownVector() {
        // SHA-256("hello") = 2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824
        let sha = DylibInstaller.sha12(of: Data("hello".utf8))
        XCTAssertEqual(sha, "2cf24dba5fb0")
    }

    func testInstallDirShape() {
        let root = URL(fileURLWithPath: "/tmp/MockMyCamTest")
        let dir = DylibInstaller.installDir(root: root, sha12: "2cf24dba5fb0")
        XCTAssertEqual(dir.path, "/tmp/MockMyCamTest/builds/2cf24dba5fb0")
    }

    func testInstallCopiesAndSetsPermissions() throws {
        // Use a sandboxed temp "app support" by installing then checking the file.
        let src = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("fake-\(UUID().uuidString).dylib")
        let bytes = Data((0..<128).map { UInt8($0) })
        try bytes.write(to: src)
        defer { try? FileManager.default.removeItem(at: src) }

        let appName = "MockMyCamTest-\(UUID().uuidString)"
        let dest = try DylibInstaller.install(dylibAt: src, appName: appName)
        defer {
            let root = try? DylibInstaller.appSupportRoot(appName: appName)
            if let root { try? FileManager.default.removeItem(at: root) }
        }

        XCTAssertTrue(dest.path.contains("/builds/\(DylibInstaller.sha12(of: bytes))/VirtualCamera.dylib"))
        XCTAssertEqual(try Data(contentsOf: dest), bytes)
        let perms = try FileManager.default.attributesOfItem(atPath: dest.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(perms?.int16Value, 0o755)
    }
}
