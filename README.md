# MockMyCam

A macOS menu-bar app that feeds a **fake camera into the running iOS Simulator** — so a
simulator app sees a "real" camera where Apple normally provides none. Use your Mac's
webcam as a live feed, or mock an image / looped video.

<p align="center"><em>Webcam · Image · Video → /tmp/SimCam.bgra → injected into the sim's AVFoundation</em></p>

## How it works

```
webcam / image / video  →  BGRAConverter  →  FramePipeline  →  SharedFrameWriter  →  /tmp/SimCam.bgra (mmap)
                                                                                            │ reads
menu-bar UI  →  DylibInstaller + SimulatorController (xcrun simctl)  ──inject──►  VirtualCamera.dylib (in the sim app)
```

- MockMyCam writes BGRA frames into a memory-mapped file (`/tmp/SimCam.bgra`). `/tmp` inside
  the simulator is the host's `/private/tmp`, so the same bytes are visible to both.
- It injects `VirtualCamera.dylib` into a simulator app via
  `xcrun simctl spawn <udid> launchctl setenv DYLD_INSERT_LIBRARIES …`. The dylib swizzles
  `AVCaptureVideoPreviewLayer` (and photo capture / image picker) to render those frames.
- The dylib is **vendored from [baguette](https://github.com/tddworks/baguette)** (Apache-2.0).
  We build it from source (`Scripts/build-dylib.sh`) and bundle it; see `ThirdParty/VirtualCamera/`.

## Requirements

- Apple Silicon Mac, macOS 14+
- Xcode 16+ with an iOS Simulator runtime (tested on Xcode 26 / iOS 26.3)

## Build & run

```bash
make app     # builds the dylib + release app → build/MockMyCam.app
make run     # launches it (menu-bar icon: camera.viewfinder)
```

## Using it

1. **Boot a simulator** (Xcode ▸ Open Developer Tool ▸ Simulator, or run your app once).
2. Click the menu-bar icon and pick your **Simulator** from the dropdown.
3. Pick a **source**: Webcam (choose a camera), Image, or Video. Click **Start**.
   You'll see a live preview of the outgoing feed.
4. Click **Arm** — installs + injects the dylib into the selected simulator.
5. Click **Relaunch app…** and choose your app. It relaunches with the camera injected.
   *(Apps must be (re)launched **after** arming — `DYLD_INSERT_LIBRARIES` only applies at launch.
   Launching from Xcode after arming works too.)*
6. **Mirror** / **Fill** toggle how the frame is displayed in the sim.

On first webcam use, macOS asks for camera permission (System Settings ▸ Privacy ▸ Camera).

## Known limitations

- **Preview-layer cameras only.** The dylib hooks `AVCaptureVideoPreviewLayer`,
  `AVCapturePhotoOutput`, and `UIImagePickerController` — i.e. standard camera preview,
  photo capture, and the image picker. Apps that consume raw frames via an
  `AVCaptureVideoDataOutput` sample-buffer delegate (some barcode/ML/document scanners,
  `react-native-vision-camera`) won't receive frames. The dylib source is vendored, so this
  hook can be added later.
- **One simulator at a time** (single shared `/tmp/SimCam.bgra`).
- **Relaunch required** after arming (inherent to DYLD injection).
- EXIF-rotated still images use their stored orientation (rotation not yet auto-applied).

## Verifying

```bash
make test    # unit tests (deterministic; E2E + webcam tests are gated/skipped)
make e2e     # on-simulator end-to-end: injects a frame, screenshots, asserts pixels
             #   (needs a booted simulator)
```

The E2E suite proves the whole pipe on a real simulator: it feeds a solid color and a
red-top/blue-bottom image, then screenshots the sim and asserts the rendered pixels (incl.
orientation). Live webcam capture: `MOCKMYCAM_WEBCAM=1 swift test --filter WebcamFrameProviderTests`
(needs camera access granted to the test runner).

## Licensing

MockMyCam is licensed under the Apache License 2.0 (see `LICENSE` and `NOTICE`). It bundles `VirtualCamera.dylib`, built from sources
vendored from baguette under the Apache License 2.0 — see `ThirdParty/VirtualCamera/LICENSE`
and `ThirdParty/VirtualCamera/NOTICE`.
