# docklayout

Save a macOS Dock and switch back to it from a menu bar icon, or from the terminal.

macOS still has no Dock profiles. docklayout snapshots the apps, folders, stacks, and spacers currently on your Dock, then puts that exact row back when you ask. Icon size, autohide, magnification, and hot corners are left alone.

## Install

One command:

```bash
npx github:nicolas-webdev/docklayout
```

A dock icon appears in the menu bar. Click it to switch layouts, or to save the Dock you have arranged right now. The icon comes back the next time you log in.

You need macOS 12 or newer and Node 18 or newer. The menu bar app is built for Apple silicon. Python 3.9 ships with macOS and is what the terminal command uses.

## Menu bar

- Each saved layout is a menu item. Choose one and the Dock switches. The Dock disappears for a fraction of a second while it restarts.
- A check mark sits on the layout that matches the Dock right now.
- **Save Current Dock…** asks for a name and snapshots whatever is on screen, including folders and spacers.
- **Start at Login** is on after install. Turn it off if you only want the icon for this session.
- **Quit Dock Layout** removes the icon until the next login, or until you run the install command again.

## Terminal

The same install puts `docklayout` on your PATH (`~/.local/bin`).

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

Names are letters, numbers, `.`, `_`, and `-`, up to 64 characters.

Every switch keeps a backup of the Dock you had a moment earlier. `docklayout undo` puts that back. The ten most recent backups stay in `~/.config/docklayout/backups`.

## What is saved

Two arrays from the Dock preferences, and nothing else:

- `persistent-apps`, the app side, including spacers
- `persistent-others`, folders and stacks

Each tile's bookmark data is stored as-is. The tool does not rebuild the Dock from a list of app names, so order and spacers survive.

Saved layouts live in `~/.config/docklayout/layouts/<name>.plist` on your Mac. They can contain paths to apps on that computer. docklayout never uploads them.

```bash
export DOCKLAYOUT_DIR="$HOME/.config/docklayout"
```

## Remove it

```bash
npx github:nicolas-webdev/docklayout uninstall
```

Saved layouts stay in `~/.config/docklayout/layouts`. Delete that folder if you want them gone too.

## Homebrew

The formula installs the terminal command only. The menu bar app is the `npx` command above.

```bash
brew tap nicolas-webdev/docklayout https://github.com/nicolas-webdev/docklayout
brew install docklayout
```

## Raycast

This is not part of the install. To generate script commands for the layouts you already saved:

```bash
docklayout raycast
```

Then add `~/raycast-scripts` once in Raycast Settings → Extensions → Script Commands.

## License

MIT. See [LICENSE](LICENSE).
