import Foundation

/// Pure `xcrun simctl` argument builders — kept separate from execution so they
/// can be unit-tested without a running simulator.
public enum Simctl {
    public static func armArgs(udid: String, dylibPath: String) -> [String] {
        ["simctl", "spawn", udid, "launchctl", "setenv", "DYLD_INSERT_LIBRARIES", dylibPath]
    }
    public static func disarmArgs(udid: String) -> [String] {
        ["simctl", "spawn", udid, "launchctl", "unsetenv", "DYLD_INSERT_LIBRARIES"]
    }
    public static func launchArgs(udid: String, bundleID: String) -> [String] {
        ["simctl", "launch", udid, bundleID]
    }
    public static func terminateArgs(udid: String, bundleID: String) -> [String] {
        ["simctl", "terminate", udid, bundleID]
    }
    public static func installArgs(udid: String, appPath: String) -> [String] {
        ["simctl", "install", udid, appPath]
    }
    public static func screenshotArgs(udid: String, path: String) -> [String] {
        ["simctl", "io", udid, "screenshot", path]
    }
    public static let listDevicesArgs = ["simctl", "list", "devices", "--json"]
    public static func listAppsArgs(udid: String) -> [String] {
        ["simctl", "listapps", udid]
    }
}

/// An app installed in a simulator (from `simctl listapps`).
public struct InstalledApp: Sendable, Identifiable {
    public let bundleID: String
    public let name: String
    public let type: String
    public var id: String { bundleID }
}

public struct SimDevice: Codable, Sendable {
    public let udid: String
    public let name: String
    public let state: String
    public let isAvailable: Bool?
}

public enum SimulatorError: Error {
    case command(args: [String], exit: Int32, stderr: String)
    case decode(String)
}

/// Executes the `Simctl` commands.
public struct SimulatorController {
    public init() {}

    @discardableResult
    private func runChecked(_ args: [String], allowFailure: Bool = false) throws -> ProcessResult {
        let result = try ProcessRunner.xcrun(args)
        if result.exitCode != 0 && !allowFailure {
            throw SimulatorError.command(args: args, exit: result.exitCode, stderr: result.stderr)
        }
        return result
    }

    /// All currently booted simulators.
    public func bootedDevices() throws -> [SimDevice] {
        let result = try runChecked(Simctl.listDevicesArgs)
        struct DeviceList: Codable { let devices: [String: [SimDevice]] }
        guard let data = result.stdout.data(using: .utf8) else {
            throw SimulatorError.decode("simctl list produced no stdout")
        }
        let list = try JSONDecoder().decode(DeviceList.self, from: data)
        return list.devices.values.flatMap { $0 }.filter { $0.state == "Booted" }
    }

    public func install(appPath: String, udid: String) throws {
        try runChecked(Simctl.installArgs(udid: udid, appPath: appPath))
    }

    /// Arms the simulator: every app launched afterwards inherits
    /// `DYLD_INSERT_LIBRARIES` and loads the injection dylib.
    public func arm(udid: String, dylibPath: String) throws {
        try runChecked(Simctl.armArgs(udid: udid, dylibPath: dylibPath))
    }

    public func disarm(udid: String) throws {
        try runChecked(Simctl.disarmArgs(udid: udid))
    }

    public func launch(bundleID: String, udid: String) throws {
        try runChecked(Simctl.launchArgs(udid: udid, bundleID: bundleID))
    }

    /// Terminate is best-effort: it's expected to fail if the app isn't running.
    public func terminate(bundleID: String, udid: String) throws {
        try runChecked(Simctl.terminateArgs(udid: udid, bundleID: bundleID), allowFailure: true)
    }

    public func screenshot(to path: String, udid: String) throws {
        try runChecked(Simctl.screenshotArgs(udid: udid, path: path))
    }

    /// Apps installed on the simulator. `simctl listapps` emits a (text) plist,
    /// which PropertyListSerialization parses directly.
    public func installedApps(udid: String, userOnly: Bool = true) throws -> [InstalledApp] {
        let result = try runChecked(Simctl.listAppsArgs(udid: udid))
        return Self.parseInstalledApps(Data(result.stdout.utf8), userOnly: userOnly)
    }

    public static func parseInstalledApps(_ data: Data, userOnly: Bool = true) -> [InstalledApp] {
        guard let plist = try? PropertyListSerialization.propertyList(
            from: data, options: [], format: nil) as? [String: Any] else { return [] }
        var apps: [InstalledApp] = []
        for (bundleID, value) in plist {
            guard let dict = value as? [String: Any] else { continue }
            let type = dict["ApplicationType"] as? String ?? ""
            if userOnly && type != "User" { continue }
            let name = (dict["CFBundleDisplayName"] as? String)
                ?? (dict["CFBundleName"] as? String) ?? bundleID
            apps.append(InstalledApp(bundleID: bundleID, name: name, type: type))
        }
        return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
