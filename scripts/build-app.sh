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

# Build each architecture on its own and merge with lipo. An architecture that
# can't be linked here (x86_64 with only the Command Line Tools, for one) is
# skipped with a warning rather than failing the build.
built=()
for arch in $ARCHS; do
  if swift build -c release --arch "$arch" --product DockLayoutApp \
     && swift build -c release --arch "$arch" --product docklayout; then
    built+=("$(swift build -c release --arch "$arch" --show-bin-path)")
  else
    echo "warning: skipping $arch, it did not build" >&2
  fi
done
(( ${#built} > 0 )) || { echo "error: nothing built" >&2; exit 1; }
echo "Architectures: ${(j: :)ARCHS} → built ${#built}"

lipo -create ${^built}/DockLayoutApp -output "$APP/Contents/MacOS/DockLayout"
lipo -create ${^built}/docklayout -output "$APP/Contents/Helpers/docklayout"

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
