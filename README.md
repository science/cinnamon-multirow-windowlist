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

### Development (symlink)

```bash
# Clone the repo
git clone <repo-url> ~/dev/cinnamon-multirow-windowlist
cd ~/dev/cinnamon-multirow-windowlist

# Symlink into Cinnamon's applet directory
ln -s "$(pwd)" ~/.local/share/cinnamon/applets/multirow-window-list@cinnamon

# Restart Cinnamon (Alt+F2 → r → Enter, or:)
cinnamon --replace &
```

### Manual install (copy)

```bash
# Copy files to Cinnamon applet directory
mkdir -p ~/.local/share/cinnamon/applets/multirow-window-list@cinnamon
cp applet.js helpers.js metadata.json settings-schema.json \
   ~/.local/share/cinnamon/applets/multirow-window-list@cinnamon/

# Restart Cinnamon
cinnamon --replace &
```

### Enable the applet

1. Right-click the panel → **Applets**
2. Search for "Multi-Row Window List"
3. Add it to your panel
4. (Optional) Remove the stock "Window list" applet to avoid duplicates

> **Note**: This applet has the `windowattentionhandler` role, same as the stock window list. Only one applet with this role should be active at a time.

## Configuration

Right-click the applet → **Configure**:

| Setting | Default | Description |
|---------|---------|-------------|
| Maximum rows | 2 | How many rows before buttons stop wrapping (1-4) |
| Icon size override | 0 (auto) | Force icon size in pixels, or 0 for auto-scaling |
| Label font size | 0 (system) | Force font size in pt, or 0 for system default |
| Allow text wrap | On | Let titles wrap to multiple lines in spacious mode |

## Uninstall

The included script removes the applet from dconf and deletes the symlink/directory. Safe to run from a TTY if Cinnamon has crashed:

```bash
./uninstall.sh
```

Then restart Cinnamon (`Alt+F2 → r → Enter`, or from a TTY: `DISPLAY=:0 cinnamon --replace &`).

## Running Tests

```bash
npm test
```

52 tests covering helper calculations, settings schema validation, and applet safety checks.

## License

Based on the stock Cinnamon window-list applet (GPL-2.0).
