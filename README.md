# Multi-Row Window List

A Cinnamon desktop applet that wraps window buttons into multiple rows on tall panels. If you use a bottom panel taller than the default, this applet fills the space with stacked rows of window buttons instead of one wide row with wasted vertical space.

Forked from the stock `window-list@cinnamon.org`.

Tested on Cinnamon 6.0.4 (Ubuntu 24.04) — full E2E suite in a VM matching the target environment, plus daily use on a live desktop.

## Why?

If you keep a lot of windows open — a dozen terminals, a few browsers, editors, chats — the stock window list crushes them all into one row. Past ten or so windows the buttons become unreadable slivers, and telling one terminal from another means hovering each button and waiting for a preview.

The obvious answer is to give the panel more height and stack the buttons. A 60px panel with two rows shows twice as many windows at full button width, with titles you can actually read at a glance. But the stock window list never wraps: on a tall panel it just draws taller one-row buttons, and the extra space is wasted. Requests to add multi-row support to Cinnamon's own window list have been declined ([#5002](https://github.com/linuxmint/Cinnamon/issues/5002), [#9746](https://github.com/linuxmint/cinnamon/issues/9746)), so it has to come from an applet.

This applet is that: the stock window list, with rows.

## What It Does

- **Multi-row wrapping**: window buttons flow into 2, 3, or 4 rows as windows pile up, using `Clutter.FlowLayout`
- **Adaptive layout**: one row uses a spacious layout (icon top-left, wrapped title text); two or more rows switch to a compact layout (icon left, single-line ellipsized title)
- **Adaptive button sizing**: when too many windows for the configured rows, buttons shrink to fit; beyond a threshold they drop labels and go icon-only
- **App grouping**: new windows from the same app are inserted next to existing windows of that app, keeping related windows together
- **Drag reorder**: drag buttons to rearrange, including across rows; the order is saved and restored across restarts
- **Window pinning**: pin rules (per app, with optional title regex) hold specific windows at fixed positions on the left of the list, surviving restarts — see `pin.sh`
- All the standard window-list features: thumbnails on hover, middle-click close, left-click minimize, workspace filtering, attention alerts

## Why not "Cinnamon Multi-Line Taskbar"?

The existing [Cinnamon Multi-Line Taskbar](https://cinnamon-spices.linuxmint.com/applets/view/123) applet occupies the same niche, but its upstream repository has been archived since 2022, it predates current Cinnamon releases, and its row count can only be changed by editing constants in `applet.js`. This applet is a fresh fork of the current stock window-list for Cinnamon 6.0 with dynamic `Clutter.FlowLayout` reflow, a full settings UI, adaptive layouts and button sizing, app grouping, and pinning.

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
npm test    # 200 unit tests
```

Tests cover helper calculations, settings schema validation, and applet safety checks (signal cleanup, timer safety, CSS box model, grouping correctness).

### VM E2E Tests

End-to-end tests run inside a libvirt/KVM VM with a real Cinnamon desktop:

```bash
bash test/vm-panel-test.sh          # Panel zone layout (0-50 windows)
bash test/vm-grouping-test.sh       # Window grouping (5 scenarios)
bash test/vm-pinning-test.sh        # Window pinning (6 scenarios)
```

Run them from inside a dev VM with a Cinnamon desktop (hostname `dev-*` or `cinnamon-dev`) — see `CLAUDE.md` for details.

## Known Issues

### Pin rules don't survive restarts for some apps (e.g. Sublime Text)

Pin rules are keyed on the app id returned by Cinnamon's `WindowTracker.get_window_app(metaWindow).get_id()`. For most apps this is the basename of a `.desktop` file (e.g. `firefox.desktop`) and is stable across sessions.

Cinnamon identifies a window's app via two strategies:
1. PID lookup: resolve `/proc/<pid>/exe` and match against `Exec=` in any installed `.desktop` file.
2. WM_CLASS lookup: match the window's `WM_CLASS` against `StartupWMClass=` in any installed `.desktop` file.

If both fail, Cinnamon synthesizes a transient app with id `window:<sequence>` where the sequence number increments per session. Pin rules saved against `window:25` will not match `window:7` after the next restart.

**Apps known to hit this:** Sublime Text snap (running binary path differs from the wrapper script in `Exec=`, and no `StartupWMClass=` line in the `.desktop` file). Other apps with sloppy `.desktop` packaging may be affected similarly — Discord, Spotify, Element, and various Electron apps are common offenders.

**Workaround per app:** drop a user-level override at `~/.local/share/applications/<app>.desktop` that adds a `StartupWMClass=<class>` line matching the window's `WM_CLASS` (run `xprop WM_CLASS` and click the window to find the class). User overrides take precedence over `/usr/share/applications/` and `/var/lib/snapd/desktop/applications/`, and survive package updates.

**Deeper fix (not yet implemented):** the applet could detect the `window:\d+` synthetic-id pattern and fall back to a stable `wmclass:<WM_CLASS>` key for pin matching. This would handle every misbehaving app at once instead of one `.desktop` override at a time, at the cost of the rare risk of two unrelated apps sharing a WM_CLASS. Revisit if the per-app workaround becomes painful.

## License

GPL-2.0-or-later — see [LICENSE](LICENSE). Forked from the stock Cinnamon window-list applet (`window-list@cinnamon.org`), Copyright (C) the Linux Mint team.
