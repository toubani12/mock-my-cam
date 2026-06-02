import SwiftUI
import AppKit
import AVFoundation
import UniformTypeIdentifiers
import MockMyCamKit

/// Coalesces high-rate frame callbacks down to a preview refresh rate, using its
/// own lock so it's safe to call from the provider's background queue.
final class FrameThrottle {
    private let interval: CFTimeInterval
    private var last: CFTimeInterval = 0
    private let lock = NSLock()
    init(fps: Double) { interval = 1.0 / fps }
    func shouldEmit() -> Bool {
        lock.lock(); defer { lock.unlock() }
        let now = CFAbsoluteTimeGetCurrent()
        guard now - last >= interval else { return false }
        last = now
        return true
    }
}

@MainActor
final class AppState: ObservableObject {
    enum SourceKind: String, CaseIterable, Identifiable {
        case webcam = "Webcam", image = "Image", video = "Video"
        var id: String { rawValue }
    }

    struct CameraInfo: Identifiable, Hashable { let id: String; let name: String }

    // Source selection
    @Published var sourceKind: SourceKind = .webcam
    @Published var cameras: [CameraInfo] = []
    @Published var selectedCameraID: String?
    @Published var imageURL: URL?
    @Published var videoURL: URL?

    // Target simulator + apps
    @Published var sims: [SimDevice] = []
    @Published var selectedSimUDID: String?
    @Published var installedApps: [InstalledApp] = []

    // State
    @Published var isStreaming = false
    @Published var isArmed = false
    @Published var mirror = false { didSet { applyFlags() } }
    @Published var fill = false { didSet { applyFlags() } }
    @Published var status = "Idle"
    @Published var previewImage: NSImage?

    private var pipeline: FramePipeline?
    private var provider: FrameProvider?
    private let sim = SimulatorController()
    private let previewThrottle = FrameThrottle(fps: 20)
    private let defaults = UserDefaults.standard

    init() {
        loadDefaults()
        refreshDevices()
    }

    // MARK: - Discovery

    func refreshDevices() {
        cameras = WebcamFrameProvider.availableCameras().map {
            CameraInfo(id: $0.uniqueID, name: $0.localizedName)
        }
        if selectedCameraID == nil { selectedCameraID = cameras.first?.id }

        sims = (try? sim.bootedDevices()) ?? []
        if selectedSimUDID == nil || !sims.contains(where: { $0.udid == selectedSimUDID }) {
            selectedSimUDID = sims.first?.udid
        }
        refreshApps()
    }

    func refreshApps() {
        guard let udid = selectedSimUDID else { installedApps = []; return }
        installedApps = (try? sim.installedApps(udid: udid)) ?? []
    }

    var selectedSimName: String {
        sims.first(where: { $0.udid == selectedSimUDID })?.name ?? "—"
    }

    // MARK: - Streaming

    func startStreaming() {
        if sourceKind == .webcam {
            ensureCameraAuthThen { [weak self] ok in
                guard let self else { return }
                if ok { self.beginStreaming() }
                else { self.status = "Camera access denied — enable it in System Settings ▸ Privacy ▸ Camera." }
            }
        } else {
            beginStreaming()
        }
    }

    private func beginStreaming() {
        guard let provider = makeProvider() else {
            status = "Pick a \(sourceKind.rawValue.lowercased()) source first."
            return
        }
        do {
            let pipeline = try ensurePipeline()
            pipeline.flags = currentFlags()
            self.provider = provider
            pipeline.use(provider)
            isStreaming = true
            status = "Streaming \(sourceKind.rawValue.lowercased())…"
        } catch {
            status = "Couldn't open the shared buffer: \(error.localizedDescription)"
        }
        saveDefaults()
    }

    func stopStreaming() {
        pipeline?.stop()
        provider = nil
        isStreaming = false
        previewImage = nil
        status = isArmed ? "Stopped (still armed)" : "Idle"
    }

    private func makeProvider() -> FrameProvider? {
        switch sourceKind {
        case .webcam:
            return WebcamFrameProvider(deviceID: selectedCameraID)
        case .image:
            guard let url = imageURL else { return nil }
            return ImageFrameProvider(url: url)
        case .video:
            guard let url = videoURL else { return nil }
            return VideoFrameProvider(url: url)
        }
    }

    private func ensurePipeline() throws -> FramePipeline {
        if let pipeline { return pipeline }
        let pipeline = try FramePipeline()
        pipeline.onFramePublished = { [weak self] frame in
            guard let self, self.previewThrottle.shouldEmit() else { return }
            guard let cg = BGRAConverter.cgImage(from: frame) else { return }
            let image = NSImage(cgImage: cg, size: NSSize(width: frame.width, height: frame.height))
            Task { @MainActor in self.previewImage = image }
        }
        self.pipeline = pipeline
        return pipeline
    }

    /// Restart the active provider (e.g. user switched camera while streaming).
    func reloadSourceIfStreaming() {
        guard isStreaming else { return }
        pipeline?.stop()
        if let provider = makeProvider() {
            self.provider = provider
            pipeline?.use(provider)
        }
    }

    // MARK: - Flags

    private func currentFlags() -> FrameLayout.Flags {
        var flags = FrameLayout.Flags()
        if mirror { flags.insert(.mirror) }
        if fill { flags.insert(.fillGravity) }
        return flags
    }

    private func applyFlags() {
        pipeline?.flags = currentFlags()
        saveDefaults()
    }

    // MARK: - Arm / Relaunch

    func arm() {
        guard let udid = selectedSimUDID else { status = "No booted simulator selected."; return }
        guard let dylibURL = BundledVirtualCamera.dylibURL else {
            status = "VirtualCamera.dylib missing from app bundle — run `make dylib`."; return
        }
        do {
            let installed = try DylibInstaller.install(dylibAt: dylibURL)
            try sim.arm(udid: udid, dylibPath: installed.path)
            isArmed = true
            status = "Armed \(selectedSimName). Relaunch your app to load the camera."
            refreshApps()
        } catch {
            status = "Arm failed: \(error.localizedDescription)"
        }
    }

    func disarm() {
        guard let udid = selectedSimUDID else { return }
        try? sim.disarm(udid: udid)
        isArmed = false
        status = isStreaming ? "Streaming (disarmed)" : "Idle"
    }

    func relaunch(_ app: InstalledApp) {
        guard let udid = selectedSimUDID else { return }
        if !isArmed { status = "Arm the simulator first, then relaunch."; return }
        try? sim.terminate(bundleID: app.bundleID, udid: udid)
        do {
            try sim.launch(bundleID: app.bundleID, udid: udid)
            status = "Relaunched \(app.name) with the camera injected."
        } catch {
            status = "Relaunch failed: \(error.localizedDescription)"
        }
    }

    // MARK: - File pickers

    func chooseImage() {
        if let url = openPanel(types: [.image]) { imageURL = url; saveDefaults(); reloadSourceIfStreaming() }
    }

    func chooseVideo() {
        if let url = openPanel(types: [.movie, .video, .mpeg4Movie, .quickTimeMovie]) {
            videoURL = url; saveDefaults(); reloadSourceIfStreaming()
        }
    }

    private func openPanel(types: [UTType]) -> URL? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = types
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        NSApp.activate(ignoringOtherApps: true)
        return panel.runModal() == .OK ? panel.url : nil
    }

    private func ensureCameraAuthThen(_ completion: @escaping (Bool) -> Void) {
        switch CameraAuthorization.status {
        case .authorized: completion(true)
        case .notDetermined:
            CameraAuthorization.request { granted in Task { @MainActor in completion(granted) } }
        default: completion(false)
        }
    }

    // MARK: - Persistence

    private func loadDefaults() {
        if let raw = defaults.string(forKey: "sourceKind"), let kind = SourceKind(rawValue: raw) { sourceKind = kind }
        selectedCameraID = defaults.string(forKey: "cameraID")
        selectedSimUDID = defaults.string(forKey: "simUDID")
        if let p = defaults.string(forKey: "imageURL") { imageURL = URL(fileURLWithPath: p) }
        if let p = defaults.string(forKey: "videoURL") { videoURL = URL(fileURLWithPath: p) }
        mirror = defaults.bool(forKey: "mirror")
        fill = defaults.bool(forKey: "fill")
    }

    private func saveDefaults() {
        defaults.set(sourceKind.rawValue, forKey: "sourceKind")
        defaults.set(selectedCameraID, forKey: "cameraID")
        defaults.set(selectedSimUDID, forKey: "simUDID")
        defaults.set(imageURL?.path, forKey: "imageURL")
        defaults.set(videoURL?.path, forKey: "videoURL")
        defaults.set(mirror, forKey: "mirror")
        defaults.set(fill, forKey: "fill")
    }
}
