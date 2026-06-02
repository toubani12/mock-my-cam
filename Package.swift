// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MockMyCam",
    platforms: [.macOS(.v14)],
    targets: [
        // All testable logic: frame pipeline, shared-memory writer, simctl
        // injection. Also bundles the prebuilt VirtualCamera.dylib as a resource
        // so it ships inside the .app and is locatable via Bundle.module.
        .target(
            name: "MockMyCamKit",
            path: "Sources/MockMyCamKit",
            resources: [
                .copy("Resources/VirtualCamera.dylib")
            ]
        ),
        // Thin menu-bar app shell (SwiftUI MenuBarExtra) over MockMyCamKit.
        .executableTarget(
            name: "MockMyCam",
            dependencies: ["MockMyCamKit"],
            path: "Sources/MockMyCam"
        ),
        .testTarget(
            name: "MockMyCamKitTests",
            dependencies: ["MockMyCamKit"],
            path: "Tests/MockMyCamKitTests"
        ),
    ],
    swiftLanguageModes: [.v5]
)
