import XCTest
@testable import MockMyCamKit

final class SimctlArgsTests: XCTestCase {
    func testArm() {
        XCTAssertEqual(
            Simctl.armArgs(udid: "U", dylibPath: "/p/VirtualCamera.dylib"),
            ["simctl", "spawn", "U", "launchctl", "setenv", "DYLD_INSERT_LIBRARIES", "/p/VirtualCamera.dylib"]
        )
    }

    func testDisarm() {
        XCTAssertEqual(
            Simctl.disarmArgs(udid: "U"),
            ["simctl", "spawn", "U", "launchctl", "unsetenv", "DYLD_INSERT_LIBRARIES"]
        )
    }

    func testLaunchTerminateInstallScreenshot() {
        XCTAssertEqual(Simctl.launchArgs(udid: "U", bundleID: "com.x"),
                       ["simctl", "launch", "U", "com.x"])
        XCTAssertEqual(Simctl.terminateArgs(udid: "U", bundleID: "com.x"),
                       ["simctl", "terminate", "U", "com.x"])
        XCTAssertEqual(Simctl.installArgs(udid: "U", appPath: "/a.app"),
                       ["simctl", "install", "U", "/a.app"])
        XCTAssertEqual(Simctl.screenshotArgs(udid: "U", path: "/s.png"),
                       ["simctl", "io", "U", "screenshot", "/s.png"])
        XCTAssertEqual(Simctl.listAppsArgs(udid: "U"),
                       ["simctl", "listapps", "U"])
    }

    func testParseInstalledAppsFiltersToUserApps() {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
          <key>com.example.App</key>
          <dict>
            <key>ApplicationType</key><string>User</string>
            <key>CFBundleDisplayName</key><string>Example</string>
          </dict>
          <key>com.apple.Maps</key>
          <dict>
            <key>ApplicationType</key><string>System</string>
            <key>CFBundleName</key><string>Maps</string>
          </dict>
        </dict></plist>
        """
        let apps = SimulatorController.parseInstalledApps(Data(xml.utf8))
        XCTAssertEqual(apps.map(\.bundleID), ["com.example.App"])
        XCTAssertEqual(apps.first?.name, "Example")

        let all = SimulatorController.parseInstalledApps(Data(xml.utf8), userOnly: false)
        XCTAssertEqual(all.count, 2)
    }
}
