# Multi-Row Window List

A Cinnamon desktop applet that wraps window buttons into multiple rows on tall panels. If you use a bottom panel taller than the default, this applet fills the space with stacked rows of window buttons instead of one wide row with wasted vertical space.

Forked from the stock `window-list@cinnamon.org`.

**Status: Alpha** — tested in a VM matching the target environment. Not yet tested on a daily-driver desktop.

## What It Does

- **Multi-row wrapping**: window buttons flow into 2, 3, or 4 rows as windows pile up, using `Clutter.FlowLayout`
- **Adaptive layout**: one row uses a spacious layout (icon top-left, wrapped title text); two or more rows switch to a compact layout (icon left, single-line ellipsized title)
- **Adaptive button sizing**: when too many windows for the configured rows, buttons shrink to fit; beyond a threshold they drop labels and go icon-only
- **App grouping**: new windows from the same app are inserted next to existing windows of that app, keeping related windows together
- **Drag reorder**: you can still drag buttons to rearrange; the order is saved and restored across restarts
- All the standard window-list features: thumbnails on hover, middle-click close, left-click minimize, workspace filtering, attention alerts

## Requirements

- Cinnamon 6.0+ (tested on 6.0.4, Ubuntu 24.04)
- Node.js 18+ (for running tests only — not needed at runtime)

## Install

```bash
git clone https://github.com/science/cinnamon-multirow-windowlist.git
cd cinnamon-multirow-windowlist
./install.sh
```

The install script validates files, checks Cinnamon is installed, creates a symlink into `~/.local/share/cinnamon/applets/`, and warns if the stock window-list is still enabled.

After running:

1. Right-click the panel → **Applets**
2. Search for **Multi-Row Window List** → add it
3. Remove the stock **Window list** (they share the `windowattentionhandler` role — only one can be active)
4. Restart Cinnamon: `Alt+F2` → type `r` → Enter

## Configuration

Right-click the applet → **Configure**:

### Multi-Row

| Setting | Default | Description |
|---------|---------|-------------|
| Maximum rows | 2 | How many rows before buttons stop wrapping (1 = single row, like stock) |
| Group windows | On | Keep windows from the same app together in the list |

### Button Appearance

| Setting | Default | Description |
|---------|---------|-------------|
| Icon size override | 0 (auto) | Force icon size in pixels, or 0 for auto-scaling to row height |
| Label font size | 0 (system) | Force font size in pt, or 0 for system default |
| Allow text wrap | On | Let titles wrap to multiple lines in spacious mode |

### Inherited Settings

All stock window-list settings are preserved: show all workspaces, attention alerts, scrolling, left-click minimize, middle-click close, button width, hover previews (thumbnail/title/nothing), and preview scale.

## Uninstall

```bash
./uninstall.sh
```

Safe to run from a TTY if Cinnamon has crashed. Removes the applet from dconf `enabled-applets` and deletes the symlink. Warns if no stock window-list is left enabled.

Then restart Cinnamon:
- **From desktop**: `Alt+F2` → type `r` → Enter
- **From TTY**: `DISPLAY=:0 cinnamon --replace &`

## Tests

```bash
npm test    # 105 unit tests
```

Tests cover helper calculations, settings schema validation, and applet safety checks (signal cleanup, timer safety, layout correctness).

## License

Based on the stock Cinnamon window-list applet (GPL-2.0).
