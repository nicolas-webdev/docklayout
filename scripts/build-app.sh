#!/bin/zsh
# Builds "dist/Dock Layout.app": the menu bar app with the docklayout CLI inside.
#
#   scripts/build-app.sh
#
# ARCHS="arm64"               build one architecture (default: arm64 x86_64, merged with lipo)
# SIGN_IDENTITY="Developer ID Application: …"   sign for distribution (default: ad-hoc)
set -euo pipefail

ROOT="${0:A:h:h}"
cd "$ROOT"

VERSION="$(sed -n 's/.*current = "\(.*\)".*/\1/p' Sources/DockLayoutCore/Version.swift)"
BUILD_NUMBER="${BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
ARCHS=(${=ARCHS:-arm64 x86_64})

APP="$ROOT/dist/Dock Layout.app"
WORK="$ROOT/.build/app"
rm -rf "$APP" "$WORK"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Helpers" "$APP/Contents/Resources/completions" "$WORK"

# Build each architecture on its own, copy its binaries aside (newer SwiftPM
# writes every architecture to the same folder), then merge with lipo. An
# architecture that can't be linked here is skipped with a warning.
built=()
for arch in $ARCHS; do
  if swift build -c release --arch "$arch" --product DockLayoutApp \
     && swift build -c release --arch "$arch" --product docklayout; then
    bin="$(swift build -c release --arch "$arch" --show-bin-path)"
    mkdir -p "$WORK/$arch"
    cp "$bin/DockLayoutApp" "$bin/docklayout" "$WORK/$arch/"
    [[ "$(lipo -archs "$WORK/$arch/DockLayoutApp")" == "$arch" ]] \
      || { echo "error: $arch build produced $(lipo -archs "$WORK/$arch/DockLayoutApp")" >&2; exit 1; }
    built+=("$WORK/$arch")
  else
    echo "warning: skipping $arch, it did not build" >&2
  fi
done
(( ${#built} > 0 )) || { echo "error: nothing built" >&2; exit 1; }

lipo -create ${^built}/DockLayoutApp -output "$APP/Contents/MacOS/DockLayout"
lipo -create ${^built}/docklayout -output "$APP/Contents/Helpers/docklayout"
echo "Architectures: $(lipo -archs "$APP/Contents/MacOS/DockLayout")"

cp Resources/Info.plist "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP/Contents/Info.plist"

swift scripts/make-icon.swift "$WORK/AppIcon.iconset"
iconutil -c icns "$WORK/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"
cp completions/zsh/_docklayout "$APP/Contents/Resources/completions/"

# Sign the helper first, then the app around it.
sign_args=(--force --options runtime --sign "$SIGN_IDENTITY")
[[ "$SIGN_IDENTITY" != "-" ]] && sign_args+=(--timestamp)
codesign "${sign_args[@]}" "$APP/Contents/Helpers/docklayout"
codesign "${sign_args[@]}" "$APP"
codesign --verify --strict "$APP"

echo "$APP ($VERSION, build $BUILD_NUMBER)"
