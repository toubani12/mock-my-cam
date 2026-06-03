#!/usr/bin/env bash
#
# Assemble and ad-hoc sign MockMyCam.app from a release build.
#
# Signing is deliberately NOT `--deep`: that would re-sign the bundled
# VirtualCamera.dylib and break the linker adhoc signature the simulator's dyld
# requires. Without --deep, codesign seals the dylib by hash without touching it.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [[ ! -f "Sources/MockMyCamKit/Resources/VirtualCamera.dylib" ]]; then
    "$ROOT/Scripts/build-dylib.sh"
fi

swift build -c release

APP="$ROOT/build/MockMyCam.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp ".build/release/MockMyCam" "$APP/Contents/MacOS/MockMyCam"
# Ship the injection dylib flat in Contents/Resources (standard layout, so
# codesign doesn't choke on unsealed content at the bundle root). Copied verbatim
# — its linker adhoc signature must survive. BundledVirtualCamera finds it via
# Bundle.main. The bytes are NOT re-signed (no --deep below).
cp "Sources/MockMyCamKit/Resources/VirtualCamera.dylib" "$APP/Contents/Resources/VirtualCamera.dylib"
cp "$ROOT/Packaging/Info.plist" "$APP/Contents/Info.plist"

codesign --force --sign - \
    --entitlements "$ROOT/Packaging/MockMyCam.entitlements" \
    --identifier com.kaarlmoroti.MockMyCam \
    "$APP" >/dev/null

echo "Built $APP"
