#!/bin/bash
# Automated VM panel zone test for the min_width fix.
#
# Tests that FlowLayout min_width = 0 override prevents panel zone squeeze
# across varying window counts: 0, 1, 10, 20, 30, 40, 50.
#
# Prerequisites:
#   - VM "cinnamon-dev" running (./vm/vm-ctl.sh start)
#   - xterm installed in VM (sudo apt install xterm)
#   - Applet loaded in Cinnamon (via symlink from virtio-fs mount)
#
# Usage:
#   ./test/vm-panel-test.sh              # Run all test cases (center zone)
#   ./test/vm-panel-test.sh --revert     # Revert to clean-baseline first
#   ./test/vm-panel-test.sh 0 1 10       # Run specific window counts only
#   ./test/vm-panel-test.sh --right-zone 0 1 10   # Test in right zone (shared with other applets)
#   ./test/vm-panel-test.sh --revert --right-zone  # Combined
#
# Each test case:
#   1. Opens N xterm windows
#   2. Waits for panel to settle
#   3. Queries panel zone widths and positions via Cinnamon D-Bus eval
#   4. Asserts right-zone applets are fully on-screen
#   5. Asserts left-zone has minimum usable width
#   6. Checks manager_container.min_width == 0
#   7. Checks for applet errors in .xsession-errors
#   8. Takes a screenshot for visual reference
#   9. Closes all test windows
#
# Exit codes:
#   0 = all tests passed
#   1 = one or more tests failed

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
VM_CTL="$PROJECT_DIR/vm/vm-ctl.sh"
SCREENSHOT_DIR="$SCRIPT_DIR/screenshots"
APPLET_UUID="multirow-window-list@cinnamon"

# --- Defaults ---
DEFAULT_COUNTS=(0 1 10 20 30 40 50)
SETTLE_TIME=3          # seconds to wait after opening windows
XTERM_SLEEP=600        # how long each xterm stays alive (seconds)
MIN_RIGHT_WIDTH=100    # right zone must be at least this wide (px)
MIN_LEFT_WIDTH=50      # left zone must be at least this wide (px)

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# --- Counters ---
TOTAL=0
PASSED=0
FAILED=0
WARNINGS=0

# --- Right-zone mode ---
RIGHT_ZONE_MODE=false
SAVED_DCONF=""

# --- SSH helpers ---
# Get VM IP once and cache it
VM_IP=""
get_vm_ip() {
    if [[ -z "$VM_IP" ]]; then
        VM_IP=$("$VM_CTL" ip)
        if [[ -z "$VM_IP" ]]; then
            echo -e "${RED}FATAL: Cannot get VM IP. Is the VM running?${NC}" >&2
            echo "  Start with: $VM_CTL start" >&2
            exit 1
        fi
    fi
    echo "$VM_IP"
}

SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=5"

vm_ssh() {
    local ip
    ip=$(get_vm_ip)
    ssh $SSH_OPTS "steve@$ip" "$@"
}

# Run a command on the VM with DISPLAY set, properly detached from SSH
vm_run() {
    vm_ssh "DISPLAY=:0 $*"
}

# Install a Python helper on the VM for quoting-safe D-Bus eval.
# JS code goes through stdin, avoiding all shell quoting issues.
install_eval_helper() {
    vm_ssh "cat > /tmp/cinnamon-eval.py" << 'EVAL_HELPER'
#!/usr/bin/env python3
"""Read JS from stdin, eval via Cinnamon D-Bus, print result."""
import subprocess, sys, re

js = sys.stdin.read().strip()
result = subprocess.run(
    ["dbus-send", "--session", "--print-reply", "--dest=org.Cinnamon",
     "/org/Cinnamon", "org.Cinnamon.Eval", "string:" + js],
    capture_output=True, text=True
)
output = result.stdout
success = "boolean true" in output
match = re.search(r'^\s*string "(.*)"$', output, re.MULTILINE)
if match:
    val = match.group(1)
    # Strip outer escaped quotes if present (D-Bus returns "\"value\"")
    if val.startswith('"') and val.endswith('"'):
        val = val[1:-1]
    # Un-escape D-Bus string escaping (\" -> ", \\\\ -> \\)
    val = val.replace('\\"', '"').replace('\\\\', '\\')
    print(val)
    sys.exit(0 if success else 1)
else:
    print("PARSE_ERROR: " + output, file=sys.stderr)
    sys.exit(1)
EVAL_HELPER
}

# Evaluate JavaScript in the running Cinnamon process via D-Bus.
# JS is piped through stdin to avoid shell quoting issues.
cinnamon_eval() {
    echo "$1" | vm_ssh "DISPLAY=:0 python3 /tmp/cinnamon-eval.py"
}

# --- Test result helpers ---
test_result() {
    local description="$1"
    local status="$2"    # pass, fail, warn
    local detail="$3"    # optional detail message
    TOTAL=$((TOTAL + 1))
    case "$status" in
        pass)
            PASSED=$((PASSED + 1))
            echo -e "  ${GREEN}PASS${NC} $description${detail:+ ($detail)}"
            ;;
        fail)
            FAILED=$((FAILED + 1))
            echo -e "  ${RED}FAIL${NC} $description${detail:+ ($detail)}"
            ;;
        warn)
            WARNINGS=$((WARNINGS + 1))
            PASSED=$((PASSED + 1))  # warnings still count as passed
            echo -e "  ${YELLOW}WARN${NC} $description${detail:+ ($detail)}"
            ;;
    esac
}

# --- Window management ---

# Open N xterm windows on the VM. Each runs "sleep" so it stays open.
# Uses setsid to fully detach from the SSH session.
open_windows() {
    local count=$1
    if [[ $count -eq 0 ]]; then
        return
    fi
    # Create a batch script on the VM via stdin to avoid quoting hell
    vm_ssh "cat > /tmp/open-test-windows.sh" <<REMOTE_SCRIPT
#!/bin/bash
for i in \$(seq 1 $count); do
    setsid xterm -title "TestWin-\$i" -e "sleep $XTERM_SLEEP" &>/dev/null &
    # Small stagger to avoid overwhelming the WM
    if (( i % 10 == 0 )); then
        sleep 0.5
    fi
done
REMOTE_SCRIPT
    vm_run "bash /tmp/open-test-windows.sh"
}

# Close all test windows
close_windows() {
    vm_run 'xdotool search --name "^TestWin-" 2>/dev/null | while read wid; do xdotool windowclose "$wid" 2>/dev/null; done' || true
    sleep 1
    # Force-kill any remaining xterms from our test
    vm_ssh 'pkill -f "xterm -title TestWin" 2>/dev/null' || true
}

# Count currently open test windows
count_windows() {
    local result
    result=$(vm_run 'xdotool search --name "^TestWin-" 2>/dev/null | wc -l' 2>/dev/null)
    echo "${result:-0}"
}

# --- Screenshot ---
take_screenshot() {
    local label="$1"
    local filename="vm-panel-${label}.png"
    mkdir -p "$SCREENSHOT_DIR"
    # xwd captures X11 display, convert to PNG
    vm_run "xwd -root -silent | convert xwd:- png:/tmp/screenshot.png" 2>/dev/null
    scp $SSH_OPTS "steve@$(get_vm_ip):/tmp/screenshot.png" "$SCREENSHOT_DIR/$filename" 2>/dev/null
    echo "$SCREENSHOT_DIR/$filename"
}

# --- Panel zone query ---
# Returns JSON with panel zone data and button visibility info
query_panel_state() {
    cinnamon_eval "
        const AppletManager = imports.ui.appletManager;
        let instances = AppletManager.getRunningInstancesForUuid(\"$APPLET_UUID\");
        let applet = instances.length > 0 ? instances[0] : null;
        let rb = Main.panel._rightBox.get_allocation_box();
        let lb = Main.panel._leftBox.get_allocation_box();
        let visibleButtons = -1;
        let actorWidth = -1;
        let parentWidth = -1;
        let containerWidth = -1;
        if (applet) {
            let panelH = applet._panelHeight || 0;
            visibleButtons = 0;
            for (let w of applet._windows) {
                if (!w.actor.visible) continue;
                let box = w.actor.get_allocation_box();
                if (box.y1 < panelH) visibleButtons++;
            }
            let ab = applet.actor.get_allocation_box();
            actorWidth = Math.round(ab.x2 - ab.x1);
            parentWidth = Math.round(applet.actor.get_parent().get_width());
            containerWidth = Math.round(applet._lastStableContainerWidth || -1);
        }
        JSON.stringify({
            screenWidth: global.screen_width,
            leftWidth: Math.round(lb.x2 - lb.x1),
            leftX1: Math.round(lb.x1),
            centerWidth: Math.round(Main.panel._centerBox.get_width()),
            rightWidth: Math.round(rb.x2 - rb.x1),
            rightX1: Math.round(rb.x1),
            rightX2: Math.round(rb.x2),
            minWidth: applet ? applet.manager_container.min_width : -999,
            minWidthSet: applet ? applet.manager_container.min_width_set : false,
            appletWindows: applet ? applet._windows.length : -1,
            appletRows: applet ? (applet._computedRows || 1) : -1,
            visibleButtons: visibleButtons,
            effectiveWidth: applet ? (applet._effectiveButtonWidth || -1) : -1,
            iconOnly: applet ? (applet._iconOnlyMode || false) : false,
            actorWidth: actorWidth,
            parentWidth: parentWidth,
            containerWidth: containerWidth
        })
    "
}

# Extract a JSON field (simple jq-free parser for integers/booleans)
json_field() {
    local json="$1"
    local field="$2"
    echo "$json" | python3 -c "import sys,json; print(json.loads(sys.stdin.read())['$field'])"
}

# --- Error log check ---
# Check .xsession-errors for applet-specific errors since a given timestamp
check_errors() {
    local since_marker="$1"
    # Look for errors mentioning our applet UUID after the marker
    local errors
    errors=$(vm_ssh "sed -n '/$since_marker/,\$p' ~/.xsession-errors 2>/dev/null \
        | grep -i '$APPLET_UUID' \
        | grep -iE 'error|critical|exception|segfault' \
        | head -20" 2>/dev/null || true)
    echo "$errors"
}

# --- Right-zone dconf manipulation ---

# Save the current enabled-applets dconf value from the VM
save_applet_dconf() {
    SAVED_DCONF=$(vm_ssh "dconf read /org/cinnamon/enabled-applets" 2>/dev/null)
    if [[ -z "$SAVED_DCONF" ]]; then
        echo -e "${RED}FATAL: Cannot read enabled-applets from VM${NC}" >&2
        exit 1
    fi
}

# Move our applet to the right zone in dconf, restart Cinnamon
move_applet_to_right_zone() {
    echo -e "${CYAN}Moving applet to right zone...${NC}"
    local new_dconf
    new_dconf=$(vm_ssh "dconf read /org/cinnamon/enabled-applets" 2>/dev/null \
        | python3 -c "
import sys, ast
raw = sys.stdin.read().strip()
entries = ast.literal_eval(raw)
updated = []
for e in entries:
    if '$APPLET_UUID' in e:
        # Format: panel1:zone:order:uuid:instance
        parts = e.split(':')
        parts[1] = 'right'
        parts[2] = '3'  # order 3 — after workspace-switcher, before systray
        updated.append(':'.join(parts))
    else:
        updated.append(e)
print(updated)
")
    if [[ -z "$new_dconf" ]]; then
        echo -e "${RED}FATAL: Failed to compute new dconf value${NC}" >&2
        exit 1
    fi
    vm_ssh "dconf write /org/cinnamon/enabled-applets \"$new_dconf\"" 2>/dev/null
    echo "  Restarting Cinnamon..."
    vm_run "cinnamon --replace &>/dev/null &" 2>/dev/null || true
    sleep 5
    echo -e "  ${GREEN}Applet moved to right zone${NC}"
}

# Restore original dconf value, restart Cinnamon
restore_applet_dconf() {
    if [[ -z "$SAVED_DCONF" ]]; then
        return
    fi
    echo ""
    echo -e "${CYAN}Restoring original applet layout...${NC}"
    vm_ssh "dconf write /org/cinnamon/enabled-applets \"$SAVED_DCONF\"" 2>/dev/null
    echo "  Restarting Cinnamon..."
    vm_run "cinnamon --replace &>/dev/null &" 2>/dev/null || true
    sleep 5
    echo -e "  ${GREEN}Original layout restored${NC}"
    SAVED_DCONF=""
}

# --- Pre-flight checks ---
preflight() {
    echo -e "${BOLD}Pre-flight checks${NC}"

    # VM running?
    local status
    status=$("$VM_CTL" status 2>/dev/null | grep -o 'running' || true)
    if [[ "$status" != "running" ]]; then
        echo -e "  ${RED}FATAL: VM is not running${NC}"
        echo "  Start with: $VM_CTL start"
        exit 1
    fi
    test_result "VM is running" "pass"

    # SSH works?
    local hostname
    hostname=$(vm_ssh "hostname" 2>/dev/null || true)
    if [[ -z "$hostname" ]]; then
        echo -e "  ${RED}FATAL: Cannot SSH to VM${NC}"
        exit 1
    fi
    test_result "SSH to VM ($hostname)" "pass"

    # xterm available?
    if ! vm_ssh "which xterm" &>/dev/null; then
        echo -e "  ${RED}FATAL: xterm not installed in VM${NC}"
        echo "  Install with: $VM_CTL ssh 'sudo apt install -y xterm'"
        exit 1
    fi
    test_result "xterm available" "pass"

    # Install D-Bus eval helper
    install_eval_helper
    test_result "D-Bus eval helper installed" "pass"

    # Applet loaded?
    local applet_check
    applet_check=$(cinnamon_eval "
        const AppletManager = imports.ui.appletManager;
        AppletManager.getRunningInstancesForUuid(\"$APPLET_UUID\").length > 0
    ")
    if [[ "$applet_check" != "true" ]]; then
        echo -e "  ${RED}FATAL: Applet not loaded in Cinnamon${NC}"
        exit 1
    fi
    test_result "Applet loaded in panel" "pass"

    # D-Bus eval working?
    local state
    state=$(query_panel_state)
    if [[ -z "$state" || "$state" == *"DBUS_EVAL_ERROR"* ]]; then
        echo -e "  ${RED}FATAL: Cannot query panel state via D-Bus${NC}"
        exit 1
    fi
    local sw
    sw=$(json_field "$state" screenWidth)
    test_result "D-Bus panel query works (screen ${sw}px)" "pass"

    # Clean slate — no leftover test windows
    close_windows
    test_result "Cleaned up leftover test windows" "pass"

    echo ""
}

# --- Run one test case ---
run_test_case() {
    local window_count=$1
    echo -e "${BOLD}Test case: ${CYAN}${window_count} windows${NC}"

    # Drop a marker in xsession-errors so we can check for new errors
    local marker="VM_PANEL_TEST_MARKER_${window_count}_$(date +%s)"
    vm_ssh "echo '$marker' >> ~/.xsession-errors" 2>/dev/null

    # Open windows
    if [[ $window_count -gt 0 ]]; then
        open_windows "$window_count"
        # Wait longer for large counts
        local wait_time=$SETTLE_TIME
        if [[ $window_count -ge 30 ]]; then
            wait_time=$((SETTLE_TIME + 2))
        fi
        if [[ $window_count -ge 50 ]]; then
            wait_time=$((SETTLE_TIME + 4))
        fi
        sleep "$wait_time"
    else
        sleep 1
    fi

    # Verify window count (xdotool)
    local actual_windows
    actual_windows=$(count_windows)
    if [[ $window_count -eq 0 ]]; then
        test_result "No test windows open" "pass" "found $actual_windows"
    elif [[ $actual_windows -ge $((window_count - 2)) ]]; then
        test_result "Windows opened" "pass" "requested=$window_count actual=$actual_windows"
    else
        test_result "Windows opened" "warn" "requested=$window_count actual=$actual_windows (some may have failed)"
    fi

    # Query panel state
    local state
    state=$(query_panel_state)

    local screen_w left_w center_w right_w right_x2 min_w min_w_set applet_win applet_rows
    local visible_btns eff_width icon_only actor_w parent_w container_w
    screen_w=$(json_field "$state" screenWidth)
    left_w=$(json_field "$state" leftWidth)
    center_w=$(json_field "$state" centerWidth)
    right_w=$(json_field "$state" rightWidth)
    right_x2=$(json_field "$state" rightX2)
    min_w=$(json_field "$state" minWidth)
    min_w_set=$(json_field "$state" minWidthSet)
    applet_win=$(json_field "$state" appletWindows)
    applet_rows=$(json_field "$state" appletRows)
    visible_btns=$(json_field "$state" visibleButtons)
    eff_width=$(json_field "$state" effectiveWidth)
    icon_only=$(json_field "$state" iconOnly)
    actor_w=$(json_field "$state" actorWidth)
    parent_w=$(json_field "$state" parentWidth)
    container_w=$(json_field "$state" containerWidth)

    echo -e "  ${CYAN}INFO${NC} zones: left=${left_w}px center=${center_w}px right=${right_w}px | rows=$applet_rows applet_wins=$applet_win"
    echo -e "  ${CYAN}INFO${NC} buttons: visible=$visible_btns effective_width=${eff_width}px icon_only=$icon_only"
    echo -e "  ${CYAN}INFO${NC} widths: actor=${actor_w}px parent=${parent_w}px container=${container_w}px"

    # --- Assertions ---

    # 1. min_width must be 0 (the fix)
    if [[ "$min_w" == "0" || "$min_w" == "0.0" ]]; then
        test_result "manager_container.min_width == 0" "pass"
    else
        test_result "manager_container.min_width == 0" "fail" "got $min_w"
    fi

    # 2. Right zone must be fully on-screen
    if [[ $right_x2 -le $screen_w ]]; then
        test_result "Right zone on-screen" "pass" "x2=${right_x2} <= screen=${screen_w}"
    else
        test_result "Right zone on-screen" "fail" "x2=${right_x2} > screen=${screen_w} — pushed off!"
    fi

    # 3. Right zone must have minimum usable width
    if [[ $right_w -ge $MIN_RIGHT_WIDTH ]]; then
        test_result "Right zone width >= ${MIN_RIGHT_WIDTH}px" "pass" "${right_w}px"
    else
        test_result "Right zone width >= ${MIN_RIGHT_WIDTH}px" "fail" "only ${right_w}px"
    fi

    # 4. Left zone must have minimum usable width
    if [[ $left_w -ge $MIN_LEFT_WIDTH ]]; then
        test_result "Left zone width >= ${MIN_LEFT_WIDTH}px" "pass" "${left_w}px"
    else
        test_result "Left zone width >= ${MIN_LEFT_WIDTH}px" "fail" "only ${left_w}px"
    fi

    # 5. Total zone widths should not exceed screen width
    local total=$((left_w + center_w + right_w))
    if [[ $total -le $((screen_w + 5)) ]]; then   # 5px tolerance for rounding
        test_result "Total zone width <= screen" "pass" "${total}px <= ${screen_w}px"
    else
        test_result "Total zone width <= screen" "fail" "${total}px > ${screen_w}px — overflow!"
    fi

    # 6. Applet should track windows (within tolerance for race conditions)
    if [[ $window_count -eq 0 ]]; then
        if [[ $applet_win -eq 0 ]]; then
            test_result "Applet shows 0 windows" "pass"
        else
            test_result "Applet shows 0 windows" "warn" "shows $applet_win (stale?)"
        fi
    else
        if [[ $applet_win -ge $((window_count - 3)) ]]; then
            test_result "Applet tracks windows" "pass" "$applet_win tracked"
        else
            test_result "Applet tracks windows" "warn" "expected ~$window_count, got $applet_win"
        fi
    fi

    # 7. For high window counts, verify multi-row is engaged
    if [[ $window_count -ge 10 ]]; then
        if [[ $applet_rows -ge 2 ]]; then
            test_result "Multi-row engaged" "pass" "$applet_rows rows"
        else
            test_result "Multi-row engaged" "warn" "only $applet_rows row(s) with $window_count windows"
        fi
    fi

    # 8. All tracked buttons must be on-screen (not clipped by row overflow)
    if [[ $window_count -gt 0 && $applet_win -gt 0 ]]; then
        if [[ $visible_btns -eq $applet_win ]]; then
            test_result "All buttons on-screen" "pass" "$visible_btns/$applet_win visible"
        elif [[ $visible_btns -ge $((applet_win - 2)) ]]; then
            test_result "All buttons on-screen" "warn" "$visible_btns/$applet_win visible (race?)"
        else
            test_result "All buttons on-screen" "fail" "only $visible_btns/$applet_win visible — overflow clipping!"
        fi
    fi

    # 9. Check for errors
    local errors
    errors=$(check_errors "$marker")
    if [[ -z "$errors" ]]; then
        test_result "No applet errors in log" "pass"
    else
        test_result "No applet errors in log" "fail" "$(echo "$errors" | wc -l) error(s)"
        echo "$errors" | head -5 | while read -r line; do
            echo -e "    ${RED}> $line${NC}"
        done
    fi

    # 10. Right-zone assertions (only when --right-zone is active)
    if $RIGHT_ZONE_MODE; then
        # Shared zone: actor allocation must be smaller than parent (zone) width
        if [[ $actor_w -lt $parent_w ]]; then
            test_result "Shared zone confirmed" "pass" "actor=${actor_w}px < parent=${parent_w}px"
        else
            test_result "Shared zone confirmed" "fail" "actor=${actor_w}px >= parent=${parent_w}px — not sharing zone!"
        fi

        # Container width should track actor allocation (minus ~10px CSS padding), not parent
        if [[ $container_w -gt 0 ]]; then
            local alloc_diff=$(( actor_w - container_w ))
            if [[ $alloc_diff -ge -20 && $alloc_diff -le 30 ]]; then
                test_result "Allocation-based width" "pass" "container=${container_w}px ~ actor=${actor_w}px (diff=${alloc_diff}px)"
            else
                test_result "Allocation-based width" "fail" "container=${container_w}px vs actor=${actor_w}px (diff=${alloc_diff}px)"
            fi
        fi

        # Container must be meaningfully less than parent (rules out old parent-based bug)
        if [[ $container_w -gt 0 && $container_w -lt $((parent_w - 50)) ]]; then
            test_result "Allocation not inflated" "pass" "container=${container_w}px << parent=${parent_w}px"
        elif [[ $container_w -gt 0 ]]; then
            test_result "Allocation not inflated" "fail" "container=${container_w}px too close to parent=${parent_w}px"
        fi
    fi

    # 11. Take screenshot
    local screenshot_label="${window_count}win"
    if $RIGHT_ZONE_MODE; then
        screenshot_label="rightzone-${window_count}win"
    fi
    local screenshot_file
    screenshot_file=$(take_screenshot "$screenshot_label" 2>/dev/null) || true
    if [[ -f "$screenshot_file" ]]; then
        echo -e "  ${CYAN}INFO${NC} screenshot: $screenshot_file"
    fi

    # Cleanup
    close_windows
    sleep 1

    echo ""
}

# --- Main ---
main() {
    echo ""
    # Parse args
    local do_revert=false
    local counts=()
    for arg in "$@"; do
        if [[ "$arg" == "--revert" ]]; then
            do_revert=true
        elif [[ "$arg" == "--right-zone" ]]; then
            RIGHT_ZONE_MODE=true
        elif [[ "$arg" =~ ^[0-9]+$ ]]; then
            counts+=("$arg")
        fi
    done
    if [[ ${#counts[@]} -eq 0 ]]; then
        counts=("${DEFAULT_COUNTS[@]}")
    fi

    local mode_label="center zone"
    if $RIGHT_ZONE_MODE; then
        mode_label="RIGHT ZONE (shared)"
    fi

    echo -e "${BOLD}══════════════════════════════════════════════${NC}"
    echo -e "${BOLD}  VM Panel Zone Test — ${mode_label}${NC}"
    echo -e "${BOLD}══════════════════════════════════════════════${NC}"
    echo ""

    # Optional: revert to clean baseline
    if $do_revert; then
        echo -e "${CYAN}Reverting to clean-baseline snapshot...${NC}"
        "$VM_CTL" revert clean-baseline
        "$VM_CTL" start
        sleep 10   # wait for boot + Cinnamon
        echo ""
    fi

    preflight

    # Restart Cinnamon to ensure latest code is loaded
    echo -e "${CYAN}Restarting Cinnamon to load latest applet code...${NC}"
    vm_run "cinnamon --replace &>/dev/null &" 2>/dev/null || true
    sleep 5
    echo ""

    # Right-zone: save dconf, move applet, set up restore trap
    if $RIGHT_ZONE_MODE; then
        save_applet_dconf
        trap restore_applet_dconf EXIT INT TERM
        move_applet_to_right_zone

        # Re-verify applet loaded after zone move
        echo -e "${BOLD}Post-move checks${NC}"
        local applet_check
        applet_check=$(cinnamon_eval "
            const AppletManager = imports.ui.appletManager;
            AppletManager.getRunningInstancesForUuid(\"$APPLET_UUID\").length > 0
        ")
        if [[ "$applet_check" != "true" ]]; then
            echo -e "  ${RED}FATAL: Applet not loaded after zone move${NC}"
            exit 1
        fi
        test_result "Applet loaded in right zone" "pass"
        echo ""
    fi

    for count in "${counts[@]}"; do
        run_test_case "$count"
    done

    # --- Summary ---
    echo -e "${BOLD}══════════════════════════════════════════════${NC}"
    echo -e "${BOLD}  Summary${NC}"
    echo -e "${BOLD}══════════════════════════════════════════════${NC}"
    echo -e "  Total:    $TOTAL"
    echo -e "  ${GREEN}Passed:   $PASSED${NC}"
    if [[ $FAILED -gt 0 ]]; then
        echo -e "  ${RED}Failed:   $FAILED${NC}"
    else
        echo -e "  Failed:   0"
    fi
    if [[ $WARNINGS -gt 0 ]]; then
        echo -e "  ${YELLOW}Warnings: $WARNINGS${NC}"
    fi
    echo ""

    if [[ $FAILED -gt 0 ]]; then
        echo -e "${RED}RESULT: FAIL${NC}"
        exit 1
    else
        echo -e "${GREEN}RESULT: PASS${NC}"
        exit 0
    fi
}

main "$@"
