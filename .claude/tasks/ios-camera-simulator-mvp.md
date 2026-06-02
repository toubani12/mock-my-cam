# iOS Simulator Camera Mock — macOS Menu-Bar App (MVP)

> Product name: **MockMyCam**. Target app camera type: **normal preview** (AVCaptureVideoPreviewLayer) — raw AVCaptureVideoDataOutput hook NOT needed for MVP. Relaunch-app helper: included.

## Goal
A macOS menu-bar app that feeds a fake camera into the running iOS Simulator, so a
simulator app sees a "real" camera. MVP supports three frame sources, wired at once:
- **Webcam passthrough** (live feed from the Mac's camera)
- **Image** upload (static image looped)
- **Video** upload (looped video file)

## Strategy (decided)
- **Reuse** baguette's `VirtualCamera.dylib` (Apache-2.0) — the hard, fragile injection layer.
- **Build** our own macOS host app (menu-bar UX + frame pipeline) around its proven contract.
- **Vendor the dylib SOURCE** (not just the binary) so we control & can extend the hooks.

## Integration contract (source-confirmed from tddworks/baguette)
- **Buffer:** `mmap` `/tmp/SimCam.bgra`, size `24 + 1280*1280*4 = 6,553,624` bytes.
- **Header (24B, little-endian):** `sequence:u32`, `timestampMs:u32`, `width:u32`, `height:u32`,
  `flags:u32` (bit0=fillGravity/aspect-fill, bit1=mirror), `reserved:u32`.
- **Pixels:** `kCVPixelFormatType_32BGRA`, tightly packed, stride = `width*4`, starts at offset 24.
  Max `width*height <= 1280*1280`.
- **Commit protocol:** write pixels first, then header (sequence++), then `msync(MS_SYNC)`.
- **Reader:** CADisplayLink polls `sequence`; unchanged/zero => no new frame; **no change for >1.0s => placeholder**.
- **Inject (arm):** `xcrun simctl spawn <udid> launchctl setenv DYLD_INSERT_LIBRARIES <dylibPath>`.
- **Disarm:** `xcrun simctl spawn <udid> launchctl unsetenv DYLD_INSERT_LIBRARIES`.
- **Relaunch required:** apps must be (re)launched AFTER arming to pick up the dylib.
- **Install path (iOS 26 dyld cache):** `~/Library/Application Support/MockMyCam/builds/<sha12>/VirtualCamera.dylib`, mode 0755, **no re-codesign**.
- **Hooks present:** `AVCaptureVideoPreviewLayer.setSession:`, `AVCapturePhotoOutput.capturePhotoWithSettings:delegate:`, `UIImagePickerController` (isSourceTypeAvailable + shutter).
- **Hooks ABSENT:** `AVCaptureVideoDataOutput` sample-buffer delegate, `AVCaptureDevice` discovery, `AVCaptureSession` start/stop.

## Architecture
```
[Frame source] -> [BGRAConverter] -> [FramePipeline] -> [SharedFrameWriter] -> /tmp/SimCam.bgra (mmap)
  webcam/image/video        tightly-packed BGRA, <=1280            header+pixels+msync        |
                                                                                              v
[Menu-bar UI / AppState] -> [DylibInstaller] + [SimulatorController(simctl)] -- injects -> VirtualCamera.dylib in sim app
```

## Tech choices
- Swift + SwiftUI, `MenuBarExtra`. Target macOS 14+ (host); Apple Silicon.
- Swift Package (executable target) + `Scripts/bundle-app.sh` to assemble a signed `.app`
  (Info.plist `LSUIElement=true`, `NSCameraUsageDescription`; camera entitlement; **non-sandboxed**
  because it must run `xcrun simctl` and write `/tmp` + `~/Library`). (Optional later: XcodeGen project.yml.)
- Dylib built from vendored ObjC source via documented `clang` fat (arm64+x86_64) `-Wl,-adhoc_codesign`.

## File layout (target)
```
Package.swift
Sources/MockCam/
  App/            MockCamApp.swift (MenuBarExtra), AppState.swift, Views/*.swift
  Core/           SharedFrameWriter.swift, FrameLayout.swift, BGRAConverter.swift,
                  FramePipeline.swift, FrameProvider.swift
  Sources/        WebcamFrameProvider.swift, ImageFrameProvider.swift, VideoFrameProvider.swift
  Injection/      DylibInstaller.swift, SimulatorController.swift, ProcessRunner.swift
  Resources/      VirtualCamera.dylib (built artifact), Info.plist, MockCam.entitlements
Tests/MockCamTests/  FrameLayoutTests.swift, SharedFrameWriterTests.swift, BGRAConverterTests.swift
ThirdParty/VirtualCamera/  SimCam*.m/.h, build.sh, LICENSE(Apache-2.0), NOTICE
Scripts/         build-dylib.sh, bundle-app.sh
Fixtures/SimProbe/  minimal iOS app w/ AVCaptureVideoPreviewLayer (for automated verification)
Makefile, README.md
```

---

## Milestones (checkable)

### Phase 0 — Preflight, scaffold, licensing  ✅ DONE
- [x] Preflight: Swift 6.2.4, Xcode 26.3, iPhoneSimulator 26.2 SDK, arm64, macOS 26.5. Booted sim: iPhone 17 Pro / iOS 26.3 (`59285BFD-0414-4A19-8EF7-4A9D5F3E3284`).
- [x] SwiftPM scaffold: `MockMyCamKit` (lib, bundles dylib) + `MockMyCam` (executable, MenuBarExtra stub) + tests. `swift build` + `swift test` green.
- [x] License: baguette = Apache-2.0 (confirmed). Vendored `ThirdParty/VirtualCamera/` source + LICENSE + authored NOTICE. Repo relicensed MIT → Apache-2.0.
- [x] `Scripts/build-dylib.sh` authored (our own clang build, mirrors upstream; not executing the fetched script).
- [x] Built dylib: universal arm64+x86_64, platform IOSSIMULATOR minos 17.0, `adhoc,linker-signed` (the form iOS 26 dyld accepts). Bundling verified via `Bundle.module` test.

### Phase 1 — Shared-memory writer + injection plumbing (prove the path)  ✅ DONE
- [x] `FrameLayout` constants (header offsets, sizes, max canvas) — single source of truth. Tests assert total = 6,553,624 + offsets.
- [x] `SharedFrameWriter`: mmap, LE header, pixels-then-header-then-msync(seq=commit), validation. Tests verify byte-exact layout + seq increments + rejects bad sizes.
- [x] `DylibInstaller`: SHA-256 -> `builds/<sha12>/`, 0755, no re-codesign, idempotent. Test pins sha12("hello")=2cf24dba5fb0.
- [x] `SimulatorController` + `ProcessRunner`: booted-device JSON parse, arm/disarm/launch/terminate/install/screenshot. Pure arg-builders unit-tested.
- [x] `Fixtures/SimProbe` + `Scripts/build-simprobe.sh`: minimal UIKit app (preview layer + magenta bg) built without an Xcode project.
- [x] **E2E smoke PASSED** (gated `MOCKMYCAM_E2E=1`, `Scripts/e2e-smoke.sh`): green frame -> install+arm -> launch SimProbe on iPhone 17 Pro/iOS 26.3 -> screenshot center pixel green. Verified programmatically (assert) AND visually (`/tmp/mockmycam-proof.png` = full-green screen). 14 unit tests green.

### Phase 2 — Frame sources (all three)  ✅ DONE
- [x] `BGRAConverter`: CGImage + CVPixelBuffer paths, tightly-packed BGRA, scale-to-fit <=1280, strips row padding. Tests pin channel order (BGRA) + sizing. **Orientation bug found & fixed**: raw CGBitmapContext is already row0=top, the explicit CTM flip was inverting it (removed).
- [x] `FrameProvider` protocol + `BGRAFrame` + `FramePipeline` (source switching, mirror/fill flags, live-preview hook).
- [x] `WebcamFrameProvider`: AVCaptureSession (hd1280x720, BGRA), device discovery (built-in/external/Continuity/DeskView), 30fps. + `CameraAuthorization`. (Capture plumbing verified live in Phase 3.)
- [x] `ImageFrameProvider`: ImageIO load, re-emit ~10fps (beats 1.0s stale timeout). Tests: loads PNG, rejects garbage.
- [x] `VideoFrameProvider`: AVPlayerItemVideoOutput, looped, ~30fps. Test generates an H.264 video and asserts frames flow at expected size.
- [x] Verified into SimProbe via screenshots: solid green (center) AND red-top/blue-bottom **orientation** through the real converter — both asserted programmatically and confirmed visually. 23 tests green (incl. 2 E2E).

### Phase 3 — Menu-bar app & packaging  ✅ DONE
- [x] `MockMyCamApp` MenuBarExtra + `@MainActor AppState` (pipeline + simctl + providers + persistence).
- [x] UI (`MenuContentView`): source segmented picker + camera/file pickers, live outgoing preview (mirrored), target-sim picker + refresh, Start/Stop, Arm/Disarm, Relaunch-app menu (user apps via `simctl listapps`), Mirror/Fill, status.
- [x] `Packaging/Info.plist` (LSUIElement, NSCameraUsageDescription) + `MockMyCam.entitlements` (camera, non-sandboxed).
- [x] `Scripts/bundle-app.sh` (assemble .app, embed SPM bundle at .app root, adhoc sign **without --deep** → dylib sha unchanged) + `Makefile`.
- [x] Verified: `--selftest` resolves bundled dylib **with `.build` hidden** (self-contained) + reaches simctl; GUI launches as menu-bar app, no crash. 25 unit tests green.
- [x] LIVE webcam-through-GUI confirmed working by user (camera permission prompt + feed into a sim app). Root cause of "not in Settings": a broken leftover bundle from the pre-fix failed `make app` (no Info.plist) — clean rebuild fixed it.

### Phase 4 — Polish & docs
- [x] README: setup, usage flow, **relaunch requirement**, **AVCaptureVideoDataOutput limitation**, verification, attribution.
- [x] Persist last-used source/camera/sim/flags (UserDefaults); graceful status messages (no sims, perm denied, missing dylib).
- [ ] (Stretch) Auto-relaunch; apply EXIF orientation to stills; extend dylib to hook `AVCaptureVideoDataOutput` (only if a target app needs raw-frame cameras).

## Verification strategy
- Unit tests for byte-exact buffer layout.
- Automated E2E via `SimProbe` + `xcrun simctl io booted screenshot` (scriptable, no human needed).
- Manual: real booted sim + a camera app for the live experience.
- Diff behavior: SimProbe shows placeholder when not armed vs injected frame when armed.

## Risks / open items
- **Hook coverage:** `AVCaptureVideoDataOutput`-based apps (some scanners/ML/RN-vision-camera) won't get
  frames via preview. Mitigation: we own the source and can add that hook (Phase 4 stretch).
- **Relaunch UX friction** (inherent to DYLD injection). Provide a one-click relaunch.
- **Single shared buffer** => one sim camera session at a time (acceptable for MVP).
- **TCC identity:** adhoc-signed bundle re-prompts on resign (fine for local; Developer ID later).
- **Upstream license** of asc-pro/SimCam to confirm in Phase 0 (baguette redistributes Apache-2.0).

## Review (filled after implementation)
- **MVP delivered.** Menu-bar app (`make app` → `build/MockMyCam.app`) streams webcam/image/video into the iOS Simulator via the vendored baguette dylib. All three sources + Arm/Disarm + Relaunch helper + Mirror/Fill + live preview.
- **Verification:** 25 unit tests (byte-exact buffer layout, BGRA channel order/scaling, image/video providers, simctl arg builders + installed-apps parsing, dylib install path) + 2 on-sim E2E tests (solid-color + image orientation, asserted via screenshot pixels) all green on iPhone 17 Pro / iOS 26.3. Packaged app verified self-contained (resolves its bundled dylib with `.build` hidden) and launches without crashing. Bundled dylib confirmed byte-identical after signing (linker adhoc sig preserved).
- **Bugs caught by tests:** a backwards vertical flip in `BGRAConverter` (caught by the orientation E2E, not by solid-color).
- **Key decisions:** wrap baguette's dylib (vendored source, Apache-2.0) vs reimplement; SwiftPM exec + bundle script vs Xcode project; global `launchctl setenv` arm model (matches Arm/Disarm UX); per-SHA dylib install + no re-codesign (iOS 26 dyld); resource bundle at `.app` root (SwiftPM accessor location).
- **Not done / follow-ups:** live webcam-through-GUI is a manual step (camera TCC grant); EXIF still-orientation; `AVCaptureVideoDataOutput` hook (only if a target app needs raw frames — not the case per user); notarized/Developer-ID distribution (currently adhoc local).
