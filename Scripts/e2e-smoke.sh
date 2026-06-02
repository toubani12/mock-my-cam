#!/usr/bin/env bash
#
# Phase 1 end-to-end smoke test: builds SimProbe, then runs the gated
# E2EInjectionTests which install+arm the dylib, feed a green frame, launch
# SimProbe on the booted simulator, screenshot it, and assert the center is green.
#
# Requires a booted iOS simulator. Run: Scripts/e2e-smoke.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Ensure the injection dylib is built into the resource bundle.
if [[ ! -f "$ROOT/Sources/MockMyCamKit/Resources/VirtualCamera.dylib" ]]; then
    "$ROOT/Scripts/build-dylib.sh"
fi

"$ROOT/Scripts/build-simprobe.sh"

export SIMPROBE_APP="$ROOT/Fixtures/SimProbe/build/SimProbe.app"
export MOCKMYCAM_E2E=1

cd "$ROOT"
swift test --filter E2EInjectionTests
