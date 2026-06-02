import XCTest
import Foundation
@testable import MockMyCamKit

final class BundledVirtualCameraTests: XCTestCase {
    /// Verifies the dylib is actually bundled and locatable via Bundle.module.
    /// This proves the resource plumbing (build-dylib.sh -> Resources -> bundle)
    /// works end to end. If this fails, run `make dylib`.
    func testDylibIsBundledAndNonTrivial() throws {
        let url = try XCTUnwrap(
            BundledVirtualCamera.dylibURL,
            "VirtualCamera.dylib missing from resource bundle — run Scripts/build-dylib.sh"
        )
        let size = try FileManager.default
            .attributesOfItem(atPath: url.path)[.size] as? Int ?? 0
        XCTAssertGreaterThan(size, 50_000, "dylib looks too small to be a real fat Mach-O")
    }
}
