#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SCRATCH_DIR="$ROOT_DIR/.build/lyrics-core"
CACHE_DIR="$ROOT_DIR/.build/swiftpm-cache"
CONFIG_DIR="$ROOT_DIR/.build/swiftpm-config"
SECURITY_DIR="$ROOT_DIR/.build/swiftpm-security"
CLANG_MODULE_CACHE_DIR="$ROOT_DIR/.build/clang-module-cache"
SWIFT_MODULE_CACHE_DIR="$ROOT_DIR/.build/swift-module-cache"

mkdir -p "$SCRATCH_DIR" "$CACHE_DIR" "$CONFIG_DIR" "$SECURITY_DIR" \
    "$CLANG_MODULE_CACHE_DIR" "$SWIFT_MODULE_CACHE_DIR"

CLANG_MODULE_CACHE_PATH="$CLANG_MODULE_CACHE_DIR" \
SWIFT_MODULECACHE_PATH="$SWIFT_MODULE_CACHE_DIR" \
swift build \
    --package-path "$ROOT_DIR/Packages/LyricsCore" \
    --scratch-path "$SCRATCH_DIR" \
    --cache-path "$CACHE_DIR" \
    --config-path "$CONFIG_DIR" \
    --security-path "$SECURITY_DIR"
