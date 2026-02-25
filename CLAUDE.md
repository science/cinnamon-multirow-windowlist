# Multi-Row Window List — Cinnamon Applet

## Project

Cinnamon 6.0.4 desktop applet (forked from stock `window-list@cinnamon.org`) that wraps window buttons into multiple rows using `Clutter.FlowLayout`. Status: **Alpha**.

- **UUID**: `multirow-window-list@cinnamon`
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
| `test/vm-panel-test.sh` | Automated VM panel zone tests (0-50 windows) |
| `test/smoke-test.sh` | Lightweight crash-detection test (Xephyr-based) |
| `vm/vm-ctl.sh` | VM lifecycle management (start, stop, ssh, snapshot, revert, viewer) |
| `vm/create-vm.sh` | Create VM from Ubuntu cloud image with cloud-init provisioning |
| `vm/clone-vm.sh` | Clone VM from clean-baseline snapshot (qcow2 CoW backing chain) |

## Commands

- **Run unit tests**: `npm test` (105+ tests, Node.js 18+)
- **Install**: `./install.sh` (validates files, creates symlink, warns about stock applet conflict)
- **Uninstall**: `./uninstall.sh` (removes from dconf + deletes symlink; safe from TTY if Cinnamon crashed)
- **Restart Cinnamon**: `Alt+F2 → r → Enter` or from TTY: `DISPLAY=:0 cinnamon --replace &`
- **Applet dir**: `~/.local/share/cinnamon/applets/multirow-window-list@cinnamon`
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

## VM Testing (REQUIRED)

### VM Infrastructure

- **VM name**: `cinnamon-dev`
- **Hypervisor**: libvirt/KVM + QEMU 8.2.2 + SPICE
- **Disk**: `/var/lib/libvirt/images/cinnamon-dev.qcow2` (qcow2, 40G virtual)
- **OS**: Ubuntu 24.04.4 LTS + Cinnamon 6.0.4 (matches host)
- **Session**: `cinnamon2d` (QXL segfaults with compositing; virtio GPU works with cinnamon2d)
- **Video**: `virtio` model (NOT QXL — QXL crashes X)
- **RAM**: 8 GiB, **CPUs**: 4
- **Login**: steve / dev (SSH key auth configured)
- **Host mount**: host `~/dev` is mounted **read-write** at `/mnt/host-dev/` via virtio-fs — code changes are instantly visible to the VM
- **Applet symlink in VM**: `~/.local/share/cinnamon/applets/multirow-window-list@cinnamon` → `/mnt/host-dev/cinnamon-multirow-windowlist`
- **Snapshot**: `clean-baseline` — working desktop with applet loaded, zero errors

### VM Management Scripts

All scripts are in `vm/`. VM needs `sudo` or `libvirt` group for `virsh`.

```bash
./vm/vm-ctl.sh start              # Start VM
./vm/vm-ctl.sh stop               # Graceful shutdown (SSH + force-off fallback)
./vm/vm-ctl.sh ssh [cmd]          # SSH into VM (or run a command)
./vm/vm-ctl.sh viewer             # Open SPICE desktop viewer
./vm/vm-ctl.sh snapshot <name>    # Create snapshot (auto-shuts down for virtiofs)
./vm/vm-ctl.sh revert <name>      # Revert to snapshot
./vm/vm-ctl.sh ip                 # Show VM IP address
./vm/vm-ctl.sh status             # Show VM state
./vm/vm-ctl.sh snapshots          # List all snapshots
./vm/vm-ctl.sh clone <name>       # Clone VM from clean-baseline (CoW)
./vm/vm-ctl.sh kill               # Force stop
./vm/vm-ctl.sh destroy            # Delete VM and storage (prompts)
```

If the session lacks the `libvirt` group, use `sg libvirt -c "virsh ..."`.

### Required Testing Workflow

After every code change that affects applet behavior:

1. **Unit tests**: `npm test` — must all pass
2. **Start VM** (if not running): `./vm/vm-ctl.sh start`
3. **Restart Cinnamon in VM** to pick up code changes:
   ```bash
   ./vm/vm-ctl.sh ssh "DISPLAY=:0 cinnamon --replace &>/dev/null &"
   ```
4. **Run automated panel test** with relevant window counts:
   ```bash
   ./test/vm-panel-test.sh 0 1 10 20    # Specific counts
   ./test/vm-panel-test.sh              # Full suite: 0, 1, 10, 20, 30, 40, 50
   ./test/vm-panel-test.sh --revert     # Revert to clean-baseline first
   ./test/vm-panel-test.sh --right-zone # Test in right zone (shared allocation)
   ```
5. **Crop and inspect screenshots** — every test run saves screenshots to `test/screenshots/`. Crop the taskbar region (65px height for 60px panel) and visually verify:
   - Button layout matches expected row count
   - Icons and labels are positioned correctly
   - Grouped windows appear adjacent
   - Zone widths are stable (left/center/right)
   - No clipping or overflow at high window counts

   Cropping command:
   ```bash
   # Crop taskbar from bottom of screenshot (65px for 60px panel height)
   convert test/screenshots/vm-panel-10win.png -gravity South -crop x65+0+0 +repage /tmp/taskbar-10win.png
   ```

### How vm-panel-test.sh Works

For each window count (0, 1, 10, 20, 30, 40, 50):

1. Opens N xterm windows via `setsid` (detached from SSH)
2. Waits for panel to settle (3-7s depending on count)
3. Queries panel state via Cinnamon D-Bus eval (`org.Cinnamon.Eval`) using a Python helper (`/tmp/cinnamon-eval.py`) that pipes JS through stdin
4. Runs 11 assertions: min_width == 0, right zone on-screen, zone widths usable, window tracking correct, multi-row engaged, buttons not clipped, no applet errors
5. Takes full-desktop screenshot to `test/screenshots/vm-panel-{N}win.png`
6. Closes all test windows, moves to next count

**D-Bus eval pattern** (for ad-hoc Cinnamon introspection):
```bash
# Install the eval helper (vm-panel-test.sh does this automatically)
./vm/vm-ctl.sh ssh "cat > /tmp/cinnamon-eval.py" << 'EOF'
#!/usr/bin/env python3
import subprocess, sys, re
js = sys.stdin.read().strip()
result = subprocess.run(
    ["dbus-send", "--session", "--print-reply", "--dest=org.Cinnamon",
     "/org/Cinnamon", "org.Cinnamon.Eval", "string:" + js],
    capture_output=True, text=True)
output = result.stdout
match = re.search(r'^\s*string "(.*)"$', output, re.MULTILINE)
if match:
    val = match.group(1)
    if val.startswith('"') and val.endswith('"'):
        val = val[1:-1]
    val = val.replace('\\"', '"').replace('\\\\', '\\')
    print(val)
    sys.exit(0 if "boolean true" in output else 1)
else:
    print("PARSE_ERROR: " + output, file=sys.stderr)
    sys.exit(1)
EOF

# Then pipe JS through stdin:
echo 'Main.panel._rightBox.get_width()' | ./vm/vm-ctl.sh ssh "DISPLAY=:0 python3 /tmp/cinnamon-eval.py"
```

### Smoke Test (Xephyr-based, no VM needed)

`test/smoke-test.sh` is a lightweight crash-detection test using Xephyr (nested X display). Verifies the applet doesn't crash Cinnamon or generate excessive errors. Useful for quick sanity checks without spinning up the VM.

```bash
bash test/smoke-test.sh    # Requires: sudo apt install xserver-xephyr
```

### VM Gotchas

- **Restart Cinnamon to pick up code changes**: `./vm/vm-ctl.sh ssh "DISPLAY=:0 cinnamon --replace &>/dev/null &"`
- **virtiofs prevents live snapshots**: vm-ctl.sh auto-shuts down before snapshotting
- **QXL crashes X**: use `virtio` video model, `cinnamon2d` session
- **SSH backgrounding**: use `setsid` to detach processes from SSH session (plain `&` leaves fds open)
- **Screenshots**: `xwd -root | convert xwd:- png:output.png` (gnome-screenshot/scrot produce black with virtio GPU)
- **virsh shutdown unreliable**: cloud-init VMs may not respond to ACPI shutdown; vm-ctl.sh uses SSH shutdown + force-off fallback
- **Cinnamon D-Bus eval quoting**: pipe JS through stdin to the Python helper — shell quoting with nested quotes is unreliable
