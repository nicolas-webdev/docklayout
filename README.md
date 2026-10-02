# docklayout

Save a macOS Dock and switch back to it from a menu bar icon, or from the terminal.

macOS still has no Dock profiles. Dock Layout snapshots the apps, folders, stacks, and spacers currently on your Dock, then puts that exact row back when you ask. Icon size, autohide, magnification, and hot corners are left alone.

## Install

1. Download `DockLayout-<version>.dmg` from [Releases](https://github.com/nicolas-webdev/docklayout/releases).
2. Drag **Dock Layout** into Applications and open it.

A dock icon appears in the menu bar. Click it to switch layouts, or to save the Dock you have arranged right now. It starts again when you log in.

You need macOS 13 or newer, on Apple silicon or Intel. Nothing else: no Python, no Node.

The app isn't notarized yet, so the first launch is blocked. Open **System Settings → Privacy & Security**, scroll down, and click **Open Anyway** next to Dock Layout. You only do this once.

Coming from the `npx` install? Open the new app once. It quits the old one, removes its login agent and Python script, and takes over Start at Login and the `docklayout` command.

## Menu bar

- Each saved layout is a menu item. Choose one and the Dock switches. The Dock disappears for a moment while it restarts, and the app waits until it's back.
- If the Dock ever isn't running, the menu shows **Restart It** at the top.
- A check mark sits on the layout that matches the Dock right now.
- **Save Current Dock…** asks for a name and snapshots whatever is on screen, including folders and spacers.
- **Undo Last Switch** puts back the Dock you had before the last switch.
- **Delete Layout** removes a saved layout.
- **Open Layouts Folder** shows the saved files in Finder.
- **Install Command Line Tool…** links `docklayout` into `~/.local/bin` (see below).
- **Start at Login** is on after install. It also appears in System Settings → General → Login Items.
- **Quit Dock Layout** removes the icon until the next login.

## Terminal

The terminal command ships inside the app. Choose **Install Command Line Tool…** in the menu to link it to `~/.local/bin/docklayout`. The link follows the app, so updating the app updates the command too.

```bash
docklayout save Work
docklayout load Personal
```

Run `docklayout` with no arguments to pick from a numbered list.

| Command | What it does |
| --- | --- |
| `docklayout save <name>` | Snapshot the current Dock |
| `docklayout load <name>` | Switch to a saved layout |
| `docklayout list` | List saved layouts |
| `docklayout active` | Print the layout that matches the Dock right now |
| `docklayout show [name]` | Print a layout, or the live Dock |
| `docklayout delete <name>` | Delete a saved layout |
| `docklayout undo` | Restore the Dock from before the last switch |
| `docklayout restart-dock` | Start the Dock again if it isn't showing |

Names are letters, numbers, `.`, `_`, and `-`, up to 64 characters.

Every switch keeps a backup of the Dock you had a moment earlier. `docklayout undo` puts that back. The ten most recent backups stay in `~/.config/docklayout/backups`.

Tab completion for zsh is in the app bundle. Add this to `~/.zshrc`:

```zsh
fpath=("/Applications/Dock Layout.app/Contents/Resources/completions" $fpath)
autoload -Uz compinit && compinit
```

## What is saved

Two arrays from the Dock preferences, and nothing else:

- `persistent-apps`, the app side, including spacers
- `persistent-others`, folders and stacks

Each tile's bookmark data is stored as-is. The tool does not rebuild the Dock from a list of app names, so order and spacers survive.

Saved layouts live in `~/.config/docklayout/layouts/<name>.plist` on your Mac. They can contain paths to apps on that computer. docklayout never uploads them.

```bash
export DOCKLAYOUT_DIR="$HOME/.config/docklayout"
```


Layouts saved by the earlier Python version load as they are.

## Remove it

Quit Dock Layout and move it to the Trash. Or, to also remove the terminal link and anything left from the `npx` install:

```bash
curl -fsSL https://raw.githubusercontent.com/nicolas-webdev/docklayout/main/uninstall.sh | zsh
```

Saved layouts stay in `~/.config/docklayout/layouts`. Delete that folder if you want them gone too, or pass `--purge`.

## Raycast

This is not part of the install. To generate script commands for the layouts you already saved:

```bash
docklayout raycast
```

Then add `~/raycast-scripts` once in Raycast Settings → Extensions → Script Commands.

## Build from source

You need Swift 6: Xcode 16 or newer, or just its Command Line Tools.

```bash
swift run DockLayoutChecks   # core checks
scripts/build-app.sh         # → dist/Dock Layout.app
scripts/make-dmg.sh          # → dist/DockLayout-<version>.dmg
```

`build-app.sh` builds for Apple silicon and Intel and merges them. Set `ARCHS=arm64` to build one. If an architecture can't be linked on your machine it is skipped with a warning. Builds are ad-hoc signed unless you set `SIGN_IDENTITY` to a Developer ID. `make-dmg.sh` notarizes when `NOTARY_PROFILE` is set.

The version lives in `Sources/DockLayoutCore/Version.swift`. Pushing a `v*` tag builds the DMG on GitHub Actions and attaches it to a release.

| Path | What it is |
| --- | --- |
| `Sources/DockLayoutCore` | Reads and writes the Dock preferences and the layout files |
| `Sources/DockLayoutApp` | The menu bar app |
| `Sources/docklayout` | The terminal command |

## License

MIT. See [LICENSE](LICENSE).
