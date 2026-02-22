# Multi-Row Window List

A Cinnamon desktop applet that wraps window buttons into multiple rows on tall panels. Forked from the stock `window-list@cinnamon.org`.

**Status: Alpha** -- functional but lightly tested. Use at your own risk.

## Features

- **Adaptive layout**: automatically switches between spacious (1 row) and compact (2+ rows) based on window count
- **Spacious mode**: small icon upper-left, title text wraps to 2 lines below
- **Compact mode**: small icon left, single-line ellipsized title right
- **Configurable**: max rows (1-4), icon size override, font size, text wrapping toggle
- Uses `Clutter.FlowLayout` for native row wrapping

## Requirements

- Cinnamon 6.0+ (tested on 6.0.4, Ubuntu 24.04)
- Node.js 18+ (for running tests only)

## Install

```bash
./install.sh
```

The install script:
1. Checks Cinnamon is installed
2. Validates all required files are present (`applet.js`, `helpers.js`, `metadata.json`, `settings-schema.json`)
3. Verifies the UUID in `metadata.json` matches
4. Creates a symlink from the repo into `~/.local/share/cinnamon/applets/`
5. Warns if the stock `window-list@cinnamon.org` is still enabled (role conflict)

After running, enable the applet:
1. Right-click the panel → **Applets**
2. Search for "Multi-Row Window List" → add it
3. Remove the stock "Window list" to avoid the `windowattentionhandler` role conflict
4. Restart Cinnamon: `Alt+F2` → type `r` → Enter

## Configuration

Right-click the applet → **Configure**:

| Setting | Default | Description |
|---------|---------|-------------|
| Maximum rows | 2 | How many rows before buttons stop wrapping (1-4) |
| Icon size override | 0 (auto) | Force icon size in pixels, or 0 for auto-scaling |
| Label font size | 0 (system) | Force font size in pt, or 0 for system default |
| Allow text wrap | On | Let titles wrap to multiple lines in spacious mode |

## Uninstall

```bash
./uninstall.sh
```

No GUI needed — safe to run from a TTY if Cinnamon has crashed.

The uninstall script:
1. Removes `multirow-window-list@cinnamon` from dconf `enabled-applets`
2. Deletes the symlink or directory at `~/.local/share/cinnamon/applets/multirow-window-list@cinnamon`
3. Warns if no stock window-list is enabled (so you know to re-add one)

Then restart Cinnamon:
- **From desktop**: `Alt+F2` → type `r` → Enter
- **From TTY** (if Cinnamon crashed): `DISPLAY=:0 cinnamon --replace &`

## Running Tests

```bash
npm test
```

52 tests covering helper calculations, settings schema validation, and applet safety checks.

## License

Based on the stock Cinnamon window-list applet (GPL-2.0).
