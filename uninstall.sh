#!/bin/zsh
set -euo pipefail

# Removes the command and tab completion.
# Saved layouts in ~/.config/docklayout/layouts are left in place.
# Pass --purge to delete those too, along with switch backups.

rm -f "${HOME}/.local/bin/docklayout"
rm -f "${HOME}/.config/docklayout/zsh/_docklayout"

if [[ "${1:-}" == "--purge" ]]; then
  rm -rf "${HOME}/.config/docklayout/layouts" "${HOME}/.config/docklayout/backups"
  echo "Removed docklayout, saved layouts, and backups."
  echo "Raycast scripts in ~/raycast-scripts were left in place. Delete the dock-*.sh files there if you want them gone."
  exit 0
fi

echo "Removed the docklayout command."
echo "Saved layouts are still in ~/.config/docklayout/layouts"
echo "Run uninstall.sh --purge to delete them."
