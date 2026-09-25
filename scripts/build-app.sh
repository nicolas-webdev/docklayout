#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h}/.."
SDK="$(xcrun --sdk macosx --show-sdk-path)"
APP="$ROOT/app/DockLayout.app"
MACOS="$APP/Contents/MacOS"
mkdir -p "$MACOS"

build_one() {
  local target="$1"
  local output="$2"
  xcrun swiftc -O -whole-module-optimization -parse-as-library \
    -target "$target" \
    -sdk "$SDK" \
    -framework AppKit \
    "$ROOT/macos/main.swift" \
    -o "$output"
}

TMP="$(mktemp -d)"
# The Command Line Tools on Apple silicon cannot link an x86_64 Swift binary.
build_one "arm64-apple-macos12.0" "$TMP/docklayout-bar-arm64"
cp "$TMP/docklayout-bar-arm64" "$MACOS/docklayout-bar"
chmod +x "$MACOS/docklayout-bar"
cp "$ROOT/macos/Info.plist" "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
echo "$APP"
