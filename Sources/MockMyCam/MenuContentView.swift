import SwiftUI
import AppKit
import MockMyCamKit

struct MenuContentView: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            targetSection
            sourceSection
            preview
            optionsSection
            Divider()
            actionsSection
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 340)
    }

    // MARK: header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "camera.viewfinder")
                .font(.title3)
                .foregroundStyle(state.isStreaming ? Color.green : Color.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text("MockMyCam").font(.headline)
                Text(state.status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
    }

    // MARK: target simulator

    private var targetSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Simulator", systemImage: "iphone").font(.caption).foregroundStyle(.secondary)
            HStack {
                if state.sims.isEmpty {
                    Text("No booted simulator").foregroundStyle(.secondary).font(.callout)
                } else {
                    Picker("", selection: $state.selectedSimUDID) {
                        ForEach(state.sims, id: \.udid) { Text($0.name).tag(Optional($0.udid)) }
                    }
                    .labelsHidden()
                    .onChange(of: state.selectedSimUDID) { state.refreshApps() }
                }
                Spacer()
                Button { state.refreshDevices() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless)
                    .help("Refresh simulators & cameras")
            }
        }
    }

    // MARK: source

    private var sourceSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("", selection: $state.sourceKind) {
                ForEach(AppState.SourceKind.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: state.sourceKind) { state.reloadSourceIfStreaming() }

            switch state.sourceKind {
            case .webcam:
                Picker("", selection: $state.selectedCameraID) {
                    ForEach(state.cameras) { Text($0.name).tag(Optional($0.id)) }
                }
                .labelsHidden()
                .onChange(of: state.selectedCameraID) { state.reloadSourceIfStreaming() }
                .disabled(state.cameras.isEmpty)
            case .image:
                filePickerRow(label: state.imageURL?.lastPathComponent ?? "No image chosen",
                              button: "Choose Image…") { state.chooseImage() }
            case .video:
                filePickerRow(label: state.videoURL?.lastPathComponent ?? "No video chosen",
                              button: "Choose Video…") { state.chooseVideo() }
            }
        }
    }

    private func filePickerRow(label: String, button: String, action: @escaping () -> Void) -> some View {
        HStack {
            Text(label).font(.callout).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            Spacer()
            Button(button, action: action)
        }
    }

    // MARK: preview

    private var preview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8).fill(Color.black)
            if let image = state.previewImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                VStack(spacing: 4) {
                    Image(systemName: "video.slash").foregroundStyle(.secondary)
                    Text(state.isStreaming ? "Waiting for frames…" : "Preview")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .frame(height: 150)
        .scaleEffect(x: state.mirror ? -1 : 1, y: 1)  // mirror the preview to match the sim
    }

    // MARK: options

    private var optionsSection: some View {
        HStack(spacing: 16) {
            Toggle("Mirror", isOn: $state.mirror)
            Toggle("Fill", isOn: $state.fill).help("Aspect-fill instead of fit (letterbox)")
            Spacer()
        }
        .toggleStyle(.checkbox)
        .font(.callout)
    }

    // MARK: actions

    private var actionsSection: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button(state.isStreaming ? "Stop" : "Start") {
                    state.isStreaming ? state.stopStreaming() : state.startStreaming()
                }
                .keyboardShortcut(.defaultAction)

                Button(state.isArmed ? "Disarm" : "Arm") {
                    state.isArmed ? state.disarm() : state.arm()
                }
                .disabled(state.selectedSimUDID == nil)
                Spacer()
            }

            Menu("Relaunch app…") {
                if state.installedApps.isEmpty {
                    Text("No user apps installed")
                } else {
                    ForEach(state.installedApps) { app in
                        Button(app.name) { state.relaunch(app) }
                    }
                }
            }
            .disabled(!state.isArmed || state.installedApps.isEmpty)
            .help("Terminate & relaunch a sim app so it loads the injected camera")
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Quit MockMyCam") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
        }
    }
}
