# Multi-Row Window List — Cinnamon Applet

## Project

Cinnamon 6.0.4 desktop applet (forked from stock `window-list@cinnamon.org`) that wraps window buttons into multiple rows using `Clutter.FlowLayout`. Status: **Alpha**.

- **UUID**: `multirow-window-list@science`
- **Target**: Cinnamon 6.0+ on Ubuntu 24.04

## Critical Rules

1. **VM testing is mandatory** — every code change that affects applet behavior must be verified in the VM before considering it done. Unit tests (`npm test`) catch logic errors; VM tests catch visual layout, Cinnamon runtime, and panel zone regressions. Both are required.
2. **Inspect cropped screenshots closely** — after VM tests, crop taskbar screenshots at 65px height (for 60px panel) and examine them for visual correctness: button layout, row wrapping, icon/label positioning, grouping order, zone widths. Screenshots are evidence — assertions alone are not sufficient.
3. **TDD throughout** — write failing tests first, then implement, then verify in VM.

## Key Files

| File | Purpose |
|------|---------|
| `applet.js` | Main applet code (GJS/Clutter/St) |
| `helpers.js` | Pure computation functions (no GJS deps, testable in Node) |
| `metadata.json` | Applet UUID, name, role |
| `settings-schema.json` | User-configurable settings (max-rows, group-windows, icon-size, font, wrap) |
| `install.sh` | Install with validation — checks files, Cinnamon version, creates symlink, warns about role conflicts |
| `uninstall.sh` | Safe removal — strips from dconf + deletes symlink. Works from TTY if Cinnamon crashed |
| `test/helpers.test.js` | Unit tests for helper functions |
| `test/schema.test.js` | Settings schema validation tests |
| `test/applet-lint.test.js` | Safety checks (cleanup, signals, timers) |
| `run.sh` | Restart Cinnamon to pick up code changes (in-VM) |
| `test/vm-panel-test.sh` | Automated panel zone tests (0-50 windows) |
| `test/vm-grouping-test.sh` | E2E test for window grouping (5 scenarios) |
| `test/vm-pinning-test.sh` | E2E test for window pinning (6 scenarios) |
| `test/smoke-test.sh` | Lightweight crash-detection test (Xephyr-based) |
| `vm/vm-ctl.sh` | VM lifecycle management — run from host (start, stop, snapshot, revert) |

## Commands

- **Run unit tests**: `npm test` (185 tests, Node.js 18+)
- **Restart Cinnamon** (pick up code changes): `./run.sh`
- **Restart + test first**: `./run.sh --test`
- **Restart + tail log**: `./run.sh --watch`
- **Install**: `./install.sh` (validates files, creates symlink, warns about stock applet conflict)
- **Uninstall**: `./uninstall.sh` (removes from dconf + deletes symlink; safe from TTY if Cinnamon crashed)
- **Manual Cinnamon restart**: `Alt+F2 → r → Enter` or `DISPLAY=:0 cinnamon --replace &>/dev/null &`
- **Applet dir**: `~/.local/share/cinnamon/applets/multirow-window-list@science`
- **dconf key**: `/org/cinnamon/enabled-applets` (list of active applets)
- **Stock applet UUID**: `window-list@cinnamon.org` (has same `windowattentionhandler` role — only one should be active)

## Architecture

- `helpers.js` exports pure functions (`calcAdaptiveRowCount`, `calcLayoutMode`, `calcAdaptiveIconSize`, `calcAdaptiveFontSize`, `calcGroupedInsertionIndex`, etc.) used by both `applet.js` and Node tests
- `applet.js` uses `require('./helpers')` for GJS, `module.exports` for Node — same file, dual runtime
- Adaptive layout: `_recomputeAdaptiveRows()` recalculates on window add/remove/allocation change
- Two modes: **spacious** (1 row — icon upper-left, text wraps below) and **compact** (2+ rows — icon left, text right, ellipsized)

## Known Constraints (Cinnamon 6.0.4)

- `ClutterText.set_max_lines()` does NOT exist — use allocation height to constrain
- `set_ellipsize(END)` suppresses `set_line_wrap(true)` — spacious mode must use `EllipsizeMode.NONE`
- `this.actor.get_size()` returns inflated preferred size — use `this.actor.get_parent().get_width()` for actual panel zone width
- `on_applet_removed_from_panel()` must destroy all window button instances to avoid GC crashes
- **St GenericContainer box model**: The `get-preferred-height` signal handler returns **content** height. St adds border+padding on top to form the allocation box. CSS margin sits outside the allocation box entirely. When computing per-row button height, the handler must subtract both border+padding (via `get_vertical_padding()` + `get_border_width()`) AND margin (via `get_length('margin-bottom')`) from the target row height. Failure to do this causes row overflow — buttons physically extend beyond the panel. Note: the default Cinnamon theme has NO margin/border on `.window-list-item-box`, so this bug only manifests with themes like Pragmatic-Darker-Blue that set `margin-bottom: 3px` and `border: 1px solid`.
- **Don't strip CSS margins with inline styles** — previously `on_orientation_changed()` used `set_style('margin-bottom: 0px')` to work around the overflow, but this only applied to buttons that existed at init time. Dynamically added buttons (new windows) retained the CSS margin. The correct fix is to account for margins in the height calculation rather than stripping them.
- **`_applySavedOrder` must be skipped when grouping is enabled** — the stock window-list saves/restores button order by XID (`lastWindowOrder` in dconf). On Cinnamon restart, `_applySavedOrder()` reorders buttons to match the stale XID list, overriding the grouped insertion done by `_addWindow()`. When `groupWindows` is true, the method returns early so grouped insertion produces the correct order during startup.

## Development Environment

**Claude Code runs inside the VM** (`cinnamon-dev`). This is the primary development environment.

### VM Infrastructure

- **VM name**: `cinnamon-dev` (hostname: `cinnamon-dev`)
- **OS**: Ubuntu 24.04.4 LTS + Cinnamon 6.0.4
- **Session**: `cinnamon2d` (virtio GPU, NOT QXL which crashes X)
- **RAM**: 8 GiB, **CPUs**: 4
- **Login**: steve / dev
- **Host connectivity**: `~/dev` → `/mnt/host-dev/` (virtio-fs, read-write) — code edits are instant
- **Screenshots to host**: `~/Pictures/host-pictures` → `/mnt/host-pictures/` — save screenshots here to view on host
- **Applet symlink**: `~/.local/share/cinnamon/applets/multirow-window-list@science` → `/mnt/host-dev/cinnamon-multirow-windowlist`
- **`DISPLAY=:0`** is set in the environment — no need to prefix commands

### Restarting Cinnamon (picking up code changes)

Cinnamon loads applet JS at startup. After editing `applet.js` or `helpers.js`, restart Cinnamon:

```bash
./run.sh              # Restart Cinnamon, wait for ready, check for errors
./run.sh --test       # Run npm test first, abort if failing
./run.sh --watch      # Restart + tail ~/.xsession-errors
```

`run.sh` does: install cinnamon-eval.py helper if missing → `setsid cinnamon --replace` → poll D-Bus until responsive → check log for applet errors.

Manual alternative: `Alt+F2 → r → Enter` (interactive) or `setsid cinnamon --replace &>/dev/null &`

### Required Testing Workflow

After every code change that affects applet behavior:

1. **Unit tests**: `npm test` — must all pass (or use `./run.sh --test`)
2. **Restart Cinnamon**: `./run.sh`
3. **Run automated panel test** with relevant window counts:
   ```bash
   bash test/vm-panel-test.sh 0 1 10 20    # Specific counts
   bash test/vm-panel-test.sh              # Full suite: 0, 1, 10, 20, 30, 40, 50
   ```
4. **Run feature-specific E2E tests**:
   ```bash
   bash test/vm-grouping-test.sh           # Window grouping (5 scenarios)
   bash test/vm-pinning-test.sh            # Window pinning (6 scenarios)
   ```
5. **Crop and inspect screenshots** — every test run saves screenshots to `test/screenshots/`. Crop the taskbar region and visually verify:
   ```bash
   convert test/screenshots/vm-panel-10win.png -gravity South -crop x65+0+0 +repage /tmp/taskbar-10win.png
   ```
   Copy to host for viewing: `cp /tmp/taskbar-10win.png ~/Pictures/host-pictures/`

### How vm-panel-test.sh Works

For each window count (0, 1, 10, 20, 30, 40, 50):

1. Opens N xterm windows via `setsid` (detached)
2. Waits for panel to settle (3-7s depending on count)
3. Queries panel state via Cinnamon D-Bus eval (`org.Cinnamon.Eval`) using `/tmp/cinnamon-eval.py`
4. Runs 11 assertions: min_width == 0, right zone on-screen, zone widths usable, window tracking correct, multi-row engaged, buttons not clipped, no applet errors
5. Takes full-desktop screenshot to `test/screenshots/vm-panel-{N}win.png`
6. Closes all test windows, moves to next count

**D-Bus eval pattern** (for ad-hoc Cinnamon introspection):
```bash
# run.sh and test scripts auto-install /tmp/cinnamon-eval.py
# Pipe JS through stdin:
echo 'Main.panel._rightBox.get_width()' | python3 /tmp/cinnamon-eval.py
```

### How vm-grouping-test.sh Works

E2E test for window grouping correctness. Runs 5 scenarios (16 assertions):

1. **Fresh grouping** — interleaved app launches, verifies same-app windows are contiguous
2. **Grouping survives restart** — verifies grouped order persists across Cinnamon restart
3. **Three apps** — adds one window per app, verifies each joins its group
4. **Rapid creation** — race condition test for WindowTracker app ID lookup
5. **Stale saved order** — scrambles container order via D-Bus, saves to dconf, restarts, verifies grouping is restored

```bash
bash test/vm-grouping-test.sh
```

**Prerequisites**: `sudo apt install -y xterm x11-apps gedit`

### How vm-pinning-test.sh Works

E2E test for window pinning feature. Runs 6 scenarios (14 assertions):

1. **Basic priority ordering** — opens windows in non-priority order, verifies sorted by priority
2. **Mixed pinned/unpinned** — pinned windows always before unpinned
3. **Survives Cinnamon restart** — pin order persists across restart
4. **Title change re-pin** — rename window title to match pin rule, verify it moves
5. **Drag inhibit** — verify `_draggable.inhibit` is true for pinned windows
6. **App-only rule** — pin rule without title filter pins all windows of that app

```bash
bash test/vm-pinning-test.sh
```

**Prerequisites**: `sudo apt install -y xterm wmctrl`

### Gotchas

- **Restart Cinnamon to pick up code changes**: `./run.sh` (or `setsid cinnamon --replace &>/dev/null &`)
- **QXL crashes X**: VM uses `virtio` video model + `cinnamon2d` session
- **Process backgrounding**: use `setsid` to fully detach processes (plain `&` may leave fds open)
- **Screenshots**: `xwd -root | convert xwd:- png:output.png` (gnome-screenshot/scrot produce black with virtio GPU)
- **D-Bus eval quoting**: pipe JS through stdin to `/tmp/cinnamon-eval.py` — shell quoting with nested quotes is unreliable
- **Test packages not pre-installed**: after clean-baseline revert, run: `sudo apt install -y xterm x11-apps gedit wmctrl`
- **Host file access**: `~/dev` → `/mnt/host-dev/` (code), `~/Pictures/host-pictures` → `/mnt/host-pictures/` (screenshots)
- **Snapshot/revert require host access**: `virsh` runs on the hypervisor host, not inside the VM

### VM Management (from host)

The `vm/` scripts are for managing the VM **from the host OS**. Since Claude Code runs inside the VM, these are for the user to run on the host when needed:

```bash
./vm/vm-ctl.sh start/stop/snapshot/revert/viewer
```
