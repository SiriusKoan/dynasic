#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
BUILD_DIR="$ROOT_DIR/.build/music-probe"
APP_DIR="$BUILD_DIR/MusicProbe.app"
SDKROOT=$(xcrun --sdk macosx --show-sdk-path)

rm -rf "$BUILD_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

swiftc \
    -parse-as-library \
    -target arm64-apple-macosx26.5 \
    -sdk "$SDKROOT" \
    -module-cache-path "$BUILD_DIR/module-cache" \
    -framework AppKit \
    -framework Combine \
    -framework Foundation \
    -framework SwiftUI \
    -o "$APP_DIR/Contents/MacOS/MusicProbe" \
    "$ROOT_DIR/MusicProbe/Sources/MusicProbe/main.swift"

cp "$ROOT_DIR/MusicProbe/Info.plist" "$APP_DIR/Contents/Info.plist"

codesign \
    --force \
    --sign - \
    --entitlements "$ROOT_DIR/MusicProbe/Entitlements.plist" \
    "$APP_DIR"

echo "Built and ad-hoc signed: $APP_DIR"
