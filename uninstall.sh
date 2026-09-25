#!/bin/zsh
set -euo pipefail

# Removes the menu bar app, the terminal command, and login startup.
# Saved layouts in ~/.config/docklayout/layouts are left in place.
# Pass --purge to delete those too, along with switch backups.

UID_NUM="$(id -u)"
launchctl bootout "gui/${UID_NUM}/com.nicolaswebdev.docklayout" 2>/dev/null || true
rm -f "${HOME}/Library/LaunchAgents/com.nicolaswebdev.docklayout.plist"
rm -rf "${HOME}/Library/Application Support/docklayout"
rm -f "${HOME}/.local/bin/docklayout"
rm -f "${HOME}/.config/docklayout/zsh/_docklayout"

if [[ "${1:-}" == "--purge" ]]; then
  rm -rf "${HOME}/.config/docklayout/layouts" "${HOME}/.config/docklayout/backups"
  echo "Removed Dock Layout, saved layouts, and backups."
  exit 0
fi

echo "Removed Dock Layout."
echo "Saved layouts are still in ~/.config/docklayout/layouts"
echo "Run uninstall.sh --purge to delete them."
