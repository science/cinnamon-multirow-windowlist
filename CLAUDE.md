# Multi-Row Window List — Cinnamon Applet

## Project

Cinnamon 6.0.4 desktop applet (forked from stock `window-list@cinnamon.org`) that wraps window buttons into multiple rows using `Clutter.FlowLayout`. Status: **Alpha**.

- **UUID**: `multirow-window-list@cinnamon`
- **Target**: Cinnamon 6.0+ on Ubuntu 24.04

## Key Files

| File | Purpose |
|------|---------|
| `applet.js` | Main applet code (GJS/Clutter/St) |
| `helpers.js` | Pure computation functions (no GJS deps, testable in Node) |
| `metadata.json` | Applet UUID, name, role |
| `settings-schema.json` | User-configurable settings (max-rows, icon-size, font, wrap) |
| `install.sh` | Install with validation — checks files, Cinnamon version, creates symlink, warns about role conflicts |
| `uninstall.sh` | Safe removal — strips from dconf + deletes symlink. Works from TTY if Cinnamon crashed |
| `test/helpers.test.js` | Unit tests for helper functions |
| `test/schema.test.js` | Settings schema validation tests |
| `test/applet-lint.test.js` | Safety checks (cleanup, signals, timers) |

## Commands

- **Run tests**: `npm test` (52 tests, Node.js 18+)
- **Install**: `./install.sh` (validates files, creates symlink, warns about stock applet conflict)
- **Uninstall**: `./uninstall.sh` (removes from dconf + deletes symlink; safe from TTY if Cinnamon crashed)
- **Restart Cinnamon**: `Alt+F2 → r → Enter` or from TTY: `DISPLAY=:0 cinnamon --replace &`
- **Applet dir**: `~/.local/share/cinnamon/applets/multirow-window-list@cinnamon`
- **dconf key**: `/org/cinnamon/enabled-applets` (list of active applets)
- **Stock applet UUID**: `window-list@cinnamon.org` (has same `windowattentionhandler` role — only one should be active)

## Architecture

- `helpers.js` exports pure functions (`calcAdaptiveRowCount`, `calcLayoutMode`, `calcAdaptiveIconSize`, `calcAdaptiveFontSize`, etc.) used by both `applet.js` and Node tests
- `applet.js` uses `require('./helpers')` for GJS, `module.exports` for Node — same file, dual runtime
- Adaptive layout: `_recomputeAdaptiveRows()` recalculates on window add/remove/allocation change
- Two modes: **spacious** (1 row — icon upper-left, text wraps below) and **compact** (2+ rows — icon left, text right, ellipsized)

## Known Constraints (Cinnamon 6.0.4)

- `ClutterText.set_max_lines()` does NOT exist — use allocation height to constrain
- `set_ellipsize(END)` suppresses `set_line_wrap(true)` — spacious mode must use `EllipsizeMode.NONE`
- `this.actor.get_size()` returns inflated preferred size — use `this.actor.get_parent().get_width()` for actual panel zone width
- `on_applet_removed_from_panel()` must destroy all window button instances to avoid GC crashes

## VM Testing

A libvirt/KVM VM (`cinnamon-dev`) mirrors the host environment. See `vm/` directory.

```bash
./vm/vm-ctl.sh start          # Start VM
./vm/vm-ctl.sh ssh [cmd]      # SSH into VM
./vm/vm-ctl.sh viewer         # Open SPICE desktop viewer
./vm/vm-ctl.sh snapshot <n>   # Create snapshot
./vm/vm-ctl.sh revert <n>     # Revert to snapshot
```

VM needs `sudo` or `libvirt` group for `virsh`. If current session lacks the group, use `sg libvirt -c "virsh ..."`.
