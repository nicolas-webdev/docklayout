# docklayout

Save a macOS Dock and switch back to it later, from the terminal or from Raycast.

macOS still has no Dock profiles. docklayout snapshots the apps, folders, stacks, and spacers currently on your Dock, then puts that exact row back when you ask. Icon size, autohide, magnification, and hot corners are left alone.

```bash
docklayout save Work
docklayout save Personal

docklayout load Work
```

The Dock disappears for a fraction of a second while it restarts. That is the switch.

## Install

You need macOS and Python 3.9 or newer. `/usr/bin/python3` on a current Mac is enough.

```bash
git clone https://github.com/nicolas-webdev/docklayout.git
cd docklayout
./install.sh
```

`install.sh` symlinks the command to `~/.local/bin/docklayout`, installs zsh tab completion, and writes Raycast commands into `~/raycast-scripts`.

Homebrew, after the tap is added:

```bash
brew tap nicolas-webdev/docklayout https://github.com/nicolas-webdev/docklayout
brew install docklayout
docklayout refresh
```

## Make a layout

Arrange the Dock by hand. Drag apps, add folders, add spacers. Then name what you see:

```bash
docklayout save Focus
```

Switch with `docklayout load Focus`, or run `docklayout` with no arguments and pick from a numbered list.

| Command | What it does |
| --- | --- |
| `docklayout save <name>` | Snapshot the current Dock |
| `docklayout load <name>` | Switch to a saved layout |
| `docklayout list` | List saved layouts |
| `docklayout show [name]` | Print a layout, or the live Dock |
| `docklayout delete <name>` | Delete a saved layout |
| `docklayout undo` | Restore the Dock from before the last switch |
| `docklayout refresh` | Regenerate the Raycast commands |

Names are letters, numbers, `.`, `_`, and `-`, up to 64 characters.

Every switch keeps a backup of the Dock you had a moment earlier. `docklayout undo` puts that back. The ten most recent backups stay in `~/.config/docklayout/backups`.

## Raycast

`docklayout save` and `docklayout refresh` write one command per layout into `~/raycast-scripts`:

- **Set Dock Layout**, a dropdown of every layout you have saved
- **Dock: Work**, **Dock: Personal**, and so on, one silent command each

Add that folder once:

1. Open Raycast Settings
2. Extensions → Script Commands
3. Add Script Directory
4. Choose `~/raycast-scripts`

Search for `Dock`. Assign a hotkey to any command from the same settings page. A new layout gets its own command the next time you save. If Raycast does not show it, run **Reload Script Directories**.

The scripts call whatever `docklayout` you used to generate them, so run `docklayout refresh` again after you move the install.

## What is saved

Two arrays from the Dock preferences, and nothing else:

- `persistent-apps`, the app side, including spacers
- `persistent-others`, folders and stacks

Each tile's bookmark data is stored as-is. The tool does not rebuild the Dock from a list of app names, so order and spacers survive.

Saved layouts live in `~/.config/docklayout/layouts/<name>.plist` on your Mac. They are ordinary preference snapshots and can contain paths to apps on that computer. docklayout never uploads them.

Override the directories if you want them somewhere else:

```bash
export DOCKLAYOUT_DIR="$HOME/.config/docklayout"
export DOCKLAYOUT_RAYCAST_DIR="$HOME/raycast-scripts"
```

## Remove it

```bash
./uninstall.sh          # command and completion only
./uninstall.sh --purge  # also delete saved layouts and backups
```

## License

MIT. See [LICENSE](LICENSE).
