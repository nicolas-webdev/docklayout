#!/bin/zsh
set -euo pipefail

# Removes Dock Layout, its terminal command, and login startup.
# Saved layouts in ~/.config/docklayout/layouts are left in place.
# Pass --purge to delete those too, along with switch backups.

APP="/Applications/Dock Layout.app"
pkill -x DockLayout 2>/dev/null || true
pkill -x docklayout-bar 2>/dev/null || true
rm -rf "$APP"

link="${HOME}/.local/bin/docklayout"
if [[ -L "$link" ]]; then
  rm -f "$link"
fi

# Left behind by the npx install (0.2 and earlier).
launchctl bootout "gui/$(id -u)/com.nicolaswebdev.docklayout" 2>/dev/null || true
rm -f "${HOME}/Library/LaunchAgents/com.nicolaswebdev.docklayout.plist"
rm -rf "${HOME}/Library/Application Support/docklayout"
rm -rf "${HOME}/.config/docklayout/zsh"

if [[ "${1:-}" == "--purge" ]]; then
  rm -rf "${HOME}/.config/docklayout/layouts" "${HOME}/.config/docklayout/backups"
  echo "Removed Dock Layout, saved layouts, and backups."
  exit 0
fi

echo "Removed Dock Layout."
echo "Saved layouts are still in ~/.config/docklayout/layouts"
echo "Run uninstall.sh --purge to delete them."
