#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

"$ROOT_DIR/scripts/build-core.sh"

if ! command -v xcodebuild >/dev/null 2>&1; then
    echo "ERROR: xcodebuild is unavailable; install Xcode before building DynamicLyrics.app." >&2
    exit 2
fi

if [ ! -d "$ROOT_DIR/dynasic.xcodeproj" ]; then
    echo "ERROR: dynasic.xcodeproj is not present; M1 app target is not bootstrapped." >&2
    exit 2
fi

xcodebuild \
    -project "$ROOT_DIR/dynasic.xcodeproj" \
    -scheme dynasic \
    -configuration Debug \
    -destination 'platform=macOS' \
    CODE_SIGNING_ALLOWED=NO \
    build
