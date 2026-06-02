#!/usr/bin/env bash
#
# Build the SimProbe verification app (a minimal iOS-Simulator app with an
# AVCaptureVideoPreviewLayer) without an Xcode project, and assemble its .app
# bundle. Used by the gated E2E injection test.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/Fixtures/SimProbe/SimProbe.swift"
PLIST="$ROOT/Fixtures/SimProbe/Info.plist"
BUILD="$ROOT/Fixtures/SimProbe/build"
APP="$BUILD/SimProbe.app"

SDK="$(xcrun --sdk iphonesimulator --show-sdk-path)"
rm -rf "$APP"
mkdir -p "$APP"

xcrun --sdk iphonesimulator swiftc \
    -sdk "$SDK" \
    -target arm64-apple-ios17.0-simulator \
    -framework UIKit -framework AVFoundation \
    -o "$APP/SimProbe" \
    "$SRC"

cp "$PLIST" "$APP/Info.plist"

echo "Built $APP"
