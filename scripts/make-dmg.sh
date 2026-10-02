#!/bin/zsh
# Packs "dist/Dock Layout.app" into dist/DockLayout-<version>.dmg.
# Run scripts/build-app.sh first.
#
# NOTARY_PROFILE=<keychain profile>   also notarize and staple (needs a Developer ID
#                                     signed build; create the profile once with
#                                     `xcrun notarytool store-credentials`)
set -euo pipefail

ROOT="${0:A:h:h}"
APP="$ROOT/dist/Dock Layout.app"
[[ -d "$APP" ]] || { echo "error: run scripts/build-app.sh first" >&2; exit 1; }

VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")"
DMG="$ROOT/dist/DockLayout-$VERSION.dmg"
STAGE="$ROOT/.build/dmg"

rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Dock Layout" -srcfolder "$STAGE" -format UDZO -ov "$DMG" >/dev/null

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
fi

echo "$DMG"
