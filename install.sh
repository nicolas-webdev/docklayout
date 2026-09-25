#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h}"
BIN_DIR="${HOME}/.local/bin"
COMPLETION_DIR="${HOME}/.config/docklayout/zsh"
ZSHRC="${HOME}/.zshrc"
MARKER="# docklayout tab completion"

mkdir -p "$BIN_DIR" "$COMPLETION_DIR"
ln -sfn "${ROOT}/bin/docklayout" "${BIN_DIR}/docklayout"
chmod +x "${ROOT}/bin/docklayout"
ln -sfn "${ROOT}/completions/zsh/_docklayout" "${COMPLETION_DIR}/_docklayout"

if [[ ! -f "$ZSHRC" ]] || ! grep -q 'docklayout/zsh' "$ZSHRC"; then
  printf '\n%s\nfpath=(~/.config/docklayout/zsh $fpath)\nautoload -Uz compinit && compinit -C\n' "$MARKER" >> "$ZSHRC"
  echo "Added tab completion to ${ZSHRC}"
fi

case ":$PATH:" in
  *":${BIN_DIR}:"*) ;;
  *)
    echo "Add ${BIN_DIR} to your PATH if docklayout is not found in a new terminal."
    ;;
esac

"${BIN_DIR}/docklayout" refresh

cat <<EOF

Installed docklayout.

  docklayout save Work
  docklayout load Work

Raycast already picks up commands written to:
  ${HOME}/raycast-scripts

Add that folder once, if it is not there yet:
  Raycast Settings → Extensions → Script Commands → Add Script Directory

Then search for "Dock" or "Set Dock Layout".
EOF
