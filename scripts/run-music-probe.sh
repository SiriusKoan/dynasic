#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
APP_PATH="$ROOT_DIR/.build/music-probe/MusicProbe.app"

if [ ! -d "$APP_PATH" ]; then
    "$ROOT_DIR/scripts/build-music-probe.sh"
fi

open "$APP_PATH"
