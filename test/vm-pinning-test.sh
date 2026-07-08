#!/bin/bash
# E2E test for window pinning feature.
#
# Verifies that pin rules correctly position windows at fixed taskbar positions,
# survive Cinnamon restarts, and lock pinned windows from drag-and-drop.
#
# Prerequisites:
#   - VM "cinnamon-dev" running (./vm/vm-ctl.sh start)
#   - xterm installed (sudo apt install xterm)
#   - Applet loaded
#
# Usage:
#   ./test/vm-pinning-test.sh              # Run all scenarios
#   ./test/vm-pinning-test.sh --revert     # Revert to clean-baseline first
#
# Exit codes:
#   0 = all tests passed
#   1 = one or more tests failed

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
VM_CTL="$PROJECT_DIR/vm/vm-ctl.sh"
SCREENSHOT_DIR="$SCRIPT_DIR/screenshots"
APPLET_UUID="multirow-window-list@science"
CONFIG_DIR="$HOME/.config/cinnamon/spices/$APPLET_UUID"

# --- Local-mode detection ---
IS_LOCAL=false
if [[ -f /mnt/host-dev/cinnamon-multirow-windowlist/applet.js ]]; then
    IS_LOCAL=true
fi

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

# --- Command helpers (dual-mode: local or SSH) ---
run_cmd() {
    if $IS_LOCAL; then
        eval "$@"
    else
        vm_ssh "$@"
    fi
}

run_display() {
    if $IS_LOCAL; then
        DISPLAY=:0 eval "$@"
    else
        vm_ssh "DISPLAY=:0 $*"
    fi
}

# --- SSH helpers (remote mode only) ---
VM_IP=""
get_vm_ip() {
    if [[ -z "$VM_IP" ]]; then
        VM_IP=$("$VM_CTL" ip)
        if [[ -z "$VM_IP" ]]; then
            echo -e "${RED}FATAL: Cannot get VM IP${NC}" >&2
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

install_eval_helper() {
    cat > /tmp/cinnamon-eval.py << 'EVAL_HELPER'
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
    if val.startswith('"') and val.endswith('"'):
        val = val[1:-1]
    val = val.replace('\\"', '"').replace('\\\\', '\\')
    print(val)
    sys.exit(0 if success else 1)
else:
    print("PARSE_ERROR: " + output, file=sys.stderr)
    sys.exit(1)
EVAL_HELPER
    if ! $IS_LOCAL; then
        vm_ssh "cat > /tmp/cinnamon-eval.py" < /tmp/cinnamon-eval.py
    fi
}

cinnamon_eval() {
    if $IS_LOCAL; then
        echo "$1" | DISPLAY=:0 python3 /tmp/cinnamon-eval.py
    else
        echo "$1" | vm_ssh "DISPLAY=:0 python3 /tmp/cinnamon-eval.py"
    fi
}

# --- Test result helpers ---
test_result() {
    local description="$1"
    local status="$2"
    local detail="$3"
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
            PASSED=$((PASSED + 1))
            echo -e "  ${YELLOW}WARN${NC} $description${detail:+ ($detail)}"
            ;;
    esac
}

# --- JS boilerplate to find our applet ---
FIND_APPLET_JS='
let _a = null;
for (let _i = 0; _i < Main.panelManager.panels.length; _i++) {
    let p = Main.panelManager.panels[_i];
    if (!p) continue;
    for (let z of [p._rightBox, p._leftBox, p._centerBox]) {
        for (let c of z.get_children()) {
            if (c._delegate && c._delegate._windows)
                _a = c._delegate;
        }
    }
}
'

# --- Query container child order with pin info ---
get_child_order() {
    cinnamon_eval "${FIND_APPLET_JS}
if (!_a) JSON.stringify({error: 'no applet'});
else {
    let tracker = imports.gi.Cinnamon.WindowTracker.get_default();
    let children = _a.manager_container.get_children();
    let r = [];
    for (let i = 0; i < children.length; i++) {
        let btn = children[i]._delegate;
        if (!btn || !btn.metaWindow) continue;
        let app = tracker.get_window_app(btn.metaWindow);
        let appId = app ? app.get_id() : 'NULL';
        let title = (btn.metaWindow.get_title() || '').substring(0,60);
        let pinPriority = (btn._pinPriority !== null && btn._pinPriority !== undefined) ? btn._pinPriority : null;
        r.push({appId: appId, title: title, pinPriority: pinPriority});
    }
    JSON.stringify(r);
}
"
}

# --- Check that pinned windows are in correct positions ---
# Takes JSON child order, checks:
#   1. All pinned windows appear before all unpinned windows
#   2. Pinned windows are sorted by priority
check_pin_order() {
    python3 -c "
import sys, json
order = json.loads(sys.stdin.read())
errors = []
pinned = [(i, w) for i, w in enumerate(order) if w.get('pinPriority') is not None]
unpinned = [(i, w) for i, w in enumerate(order) if w.get('pinPriority') is None]

# Check pinned before unpinned
if pinned and unpinned:
    last_pinned_idx = max(i for i, _ in pinned)
    first_unpinned_idx = min(i for i, _ in unpinned)
    if last_pinned_idx >= first_unpinned_idx:
        errors.append(f'Pinned window at index {last_pinned_idx} is after unpinned at {first_unpinned_idx}')

# Check pinned sorted by priority
for j in range(1, len(pinned)):
    prev_pri = pinned[j-1][1]['pinPriority']
    curr_pri = pinned[j][1]['pinPriority']
    if curr_pri < prev_pri:
        errors.append(f'Priority {curr_pri} appears after {prev_pri}')

result = {'ok': len(errors) == 0, 'errors': errors, 'pinned_count': len(pinned)}
print(json.dumps(result))
" <<< "$1"
}

# --- Window helpers ---
kill_test_windows() {
    run_display "wmctrl -l | grep -E 'PIN-TEST' | awk '{print \$1}' | xargs -r -I{} wmctrl -ic {}" 2>/dev/null || true
    sleep 1
}

open_xterm() {
    local title="$1"
    run_display "setsid xterm -T '$title' -e 'sleep 300' &>/dev/null &"
}

# --- Find the instance config file ---
find_config_file() {
    ls "$CONFIG_DIR"/*.json 2>/dev/null | head -1
}

# --- Set pin rules via config file ---
set_pin_rules() {
    local rules_json="$1"
    local config
    config=$(find_config_file)
    if [[ -z "$config" ]]; then
        echo -e "${RED}FATAL: No applet config file in $CONFIG_DIR${NC}" >&2
        exit 1
    fi
    python3 -c "
import sys, json
config_path = sys.argv[1]
new_rules = sys.argv[2]
with open(config_path) as f:
    data = json.load(f)
data['pin-rules']['value'] = new_rules
with open(config_path, 'w') as f:
    json.dump(data, f, indent=4)
" "$config" "$rules_json"
    sleep 1
}

clear_pin_rules() {
    set_pin_rules '[]'
}

# --- Preflight ---
echo -e "\n${BOLD}=== Window Pinning E2E Test ===${NC}\n"

# Handle --revert flag
if [[ "$1" == "--revert" ]]; then
    if $IS_LOCAL; then
        echo -e "${YELLOW}WARN: --revert requires host access (virsh). Skipping revert.${NC}"
    else
        echo -e "${CYAN}Reverting to clean-baseline...${NC}"
        "$VM_CTL" revert clean-baseline
        "$VM_CTL" start
        sleep 10
    fi
fi

# Preflight checks
if ! $IS_LOCAL; then
    echo -e "${CYAN}Checking VM status...${NC}"
    VM_STATE=$("$VM_CTL" status 2>/dev/null || echo "unknown")
    if [[ "$VM_STATE" != *"running"* ]]; then
        echo -e "${RED}FATAL: VM is not running (state: $VM_STATE)${NC}"
        echo "Start with: ./vm/vm-ctl.sh start"
        exit 1
    fi
    echo -e "${CYAN}Checking SSH...${NC}"
    if ! run_cmd "echo ok" &>/dev/null; then
        echo -e "${RED}FATAL: Cannot SSH into VM${NC}"
        exit 1
    fi
fi

# Install eval helper
install_eval_helper

# Install prerequisites
echo -e "${CYAN}Installing test prerequisites...${NC}"
run_cmd "which xterm &>/dev/null || sudo apt install -y xterm" &>/dev/null
run_cmd "which wmctrl &>/dev/null || sudo apt install -y wmctrl" &>/dev/null

# Clean up any leftover test windows
kill_test_windows

# Ensure grouping is disabled for cleaner pin testing
# Disable grouping for cleaner pin testing
config_file=$(find_config_file)
if [[ -n "$config_file" ]]; then
    python3 -c "
import sys, json
with open(sys.argv[1]) as f:
    data = json.load(f)
data['group-windows']['value'] = False
with open(sys.argv[1], 'w') as f:
    json.dump(data, f, indent=4)
" "$config_file"
fi

mkdir -p "$SCREENSHOT_DIR"

# ============================================================
# Scenario 1: Basic pinning — priority ordering
# ============================================================
echo -e "\n${BOLD}Scenario 1: Basic pin priority ordering${NC}"

# Set pin rules: xterm windows with specific titles get different priorities
set_pin_rules '[{"appId":"xterm.desktop","title":"PIN-TEST-A","priority":0},{"appId":"xterm.desktop","title":"PIN-TEST-B","priority":5},{"appId":"xterm.desktop","title":"PIN-TEST-C","priority":2}]'

# Open windows in non-priority order
open_xterm "PIN-TEST-B window"   # priority 5
sleep 1
open_xterm "PIN-TEST-C window"   # priority 2
sleep 1
open_xterm "PIN-TEST-A window"   # priority 0
sleep 3

# Query order
ORDER=$(get_child_order)
echo "  Button order: $ORDER"

# Check pin ordering
CHECK=$(check_pin_order "$ORDER")
IS_OK=$(echo "$CHECK" | python3 -c "import sys,json; print(json.loads(sys.stdin.read())['ok'])")
ERRORS=$(echo "$CHECK" | python3 -c "import sys,json; print(json.loads(sys.stdin.read())['errors'])")

if [[ "$IS_OK" == "True" ]]; then
    test_result "Pinned windows sorted by priority" pass
else
    test_result "Pinned windows sorted by priority" fail "$ERRORS"
fi

# Verify specific order: A (pri 0), C (pri 2), B (pri 5)
FIRST_TITLE=$(echo "$ORDER" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(d[0]['title'] if len(d)>0 else 'NONE')")
if [[ "$FIRST_TITLE" == *"PIN-TEST-A"* ]]; then
    test_result "Lowest priority window is first" pass "$FIRST_TITLE"
else
    test_result "Lowest priority window is first" fail "got: $FIRST_TITLE"
fi

# Check that pinPriority is set on the buttons
PINNED_COUNT=$(echo "$CHECK" | python3 -c "import sys,json; print(json.loads(sys.stdin.read())['pinned_count'])")
if [[ "$PINNED_COUNT" == "3" ]]; then
    test_result "All 3 windows are pinned" pass
else
    test_result "All 3 windows are pinned" fail "pinned=$PINNED_COUNT"
fi

# Take screenshot
run_display "xwd -root | convert xwd:- png:$SCREENSHOT_DIR/vm-pinning-basic.png" 2>/dev/null || true

kill_test_windows

# ============================================================
# Scenario 2: Mixed pinned and unpinned windows
# ============================================================
echo -e "\n${BOLD}Scenario 2: Mixed pinned and unpinned windows${NC}"

# Pin rule only for PIN-TEST-A
set_pin_rules '[{"appId":"xterm.desktop","title":"PIN-TEST-A","priority":0}]'

# Open unpinned first, then pinned
open_xterm "PIN-TEST-UNPIN1"
sleep 1
open_xterm "PIN-TEST-UNPIN2"
sleep 1
open_xterm "PIN-TEST-A pinned"
sleep 3

ORDER=$(get_child_order)
echo "  Button order: $ORDER"

CHECK=$(check_pin_order "$ORDER")
IS_OK=$(echo "$CHECK" | python3 -c "import sys,json; print(json.loads(sys.stdin.read())['ok'])")

if [[ "$IS_OK" == "True" ]]; then
    test_result "Pinned window before unpinned windows" pass
else
    ERRORS=$(echo "$CHECK" | python3 -c "import sys,json; print(json.loads(sys.stdin.read())['errors'])")
    test_result "Pinned window before unpinned windows" fail "$ERRORS"
fi

# Verify first window is the pinned one
FIRST_TITLE=$(echo "$ORDER" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(d[0]['title'] if len(d)>0 else 'NONE')")
if [[ "$FIRST_TITLE" == *"PIN-TEST-A"* ]]; then
    test_result "Pinned window at index 0" pass
else
    test_result "Pinned window at index 0" fail "first=$FIRST_TITLE"
fi

kill_test_windows

# ============================================================
# Scenario 3: Pinning survives Cinnamon restart
# ============================================================
echo -e "\n${BOLD}Scenario 3: Pinning survives Cinnamon restart${NC}"

set_pin_rules '[{"appId":"xterm.desktop","title":"PIN-TEST-A","priority":0},{"appId":"xterm.desktop","title":"PIN-TEST-B","priority":5}]'

open_xterm "PIN-TEST-B window"
sleep 1
open_xterm "PIN-TEST-A window"
sleep 1
open_xterm "PIN-TEST-UNPIN"
sleep 3

# Verify pre-restart order
ORDER_PRE=$(get_child_order)
echo "  Pre-restart order: $ORDER_PRE"

# Restart Cinnamon
echo "  Restarting Cinnamon..."
run_display "cinnamon --replace &>/dev/null &"
sleep 5

# Verify post-restart order
ORDER_POST=$(get_child_order)
echo "  Post-restart order: $ORDER_POST"

CHECK_POST=$(check_pin_order "$ORDER_POST")
IS_OK=$(echo "$CHECK_POST" | python3 -c "import sys,json; print(json.loads(sys.stdin.read())['ok'])")

if [[ "$IS_OK" == "True" ]]; then
    test_result "Pin order correct after Cinnamon restart" pass
else
    ERRORS=$(echo "$CHECK_POST" | python3 -c "import sys,json; print(json.loads(sys.stdin.read())['errors'])")
    test_result "Pin order correct after Cinnamon restart" fail "$ERRORS"
fi

# Verify PIN-TEST-A is still first
FIRST_TITLE=$(echo "$ORDER_POST" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(d[0]['title'] if len(d)>0 else 'NONE')")
if [[ "$FIRST_TITLE" == *"PIN-TEST-A"* ]]; then
    test_result "Pinned window stays first after restart" pass
else
    test_result "Pinned window stays first after restart" fail "first=$FIRST_TITLE"
fi

kill_test_windows

# ============================================================
# Scenario 4: Title change triggers re-pin
# ============================================================
echo -e "\n${BOLD}Scenario 4: Title change triggers re-pinning${NC}"

# Pin rule: only title matching "PINNED-NOW" gets priority 0
set_pin_rules '[{"appId":"xterm.desktop","title":"PINNED-NOW","priority":0}]'

# Open a window that does NOT match the pin rule
open_xterm "PIN-TEST-NOTYET"
sleep 1
open_xterm "PIN-TEST-OTHER"
sleep 2

# Verify it's unpinned
ORDER=$(get_child_order)
PINNED_COUNT=$(check_pin_order "$ORDER" | python3 -c "import sys,json; print(json.loads(sys.stdin.read())['pinned_count'])")
if [[ "$PINNED_COUNT" == "0" ]]; then
    test_result "No windows pinned initially" pass
else
    test_result "No windows pinned initially" fail "pinned=$PINNED_COUNT"
fi

# Rename the window title to match the pin rule
run_display "wmctrl -r 'PIN-TEST-NOTYET' -N 'PINNED-NOW test'" 2>/dev/null || true
sleep 2  # wait for debounce (300ms) + processing

ORDER=$(get_child_order)
echo "  After rename: $ORDER"
PINNED_COUNT=$(check_pin_order "$ORDER" | python3 -c "import sys,json; print(json.loads(sys.stdin.read())['pinned_count'])")
if [[ "$PINNED_COUNT" == "1" ]]; then
    test_result "Window pinned after title change" pass
else
    test_result "Window pinned after title change" fail "pinned=$PINNED_COUNT"
fi

# Verify pinned window is first
FIRST_TITLE=$(echo "$ORDER" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(d[0]['title'] if len(d)>0 else 'NONE')")
if [[ "$FIRST_TITLE" == *"PINNED-NOW"* ]]; then
    test_result "Renamed window moved to pinned position" pass
else
    test_result "Renamed window moved to pinned position" fail "first=$FIRST_TITLE"
fi

kill_test_windows

# ============================================================
# Scenario 5: Drag inhibit for pinned windows
# ============================================================
echo -e "\n${BOLD}Scenario 5: Drag inhibit on pinned windows${NC}"

set_pin_rules '[{"appId":"xterm.desktop","title":"PIN-TEST-LOCKED","priority":0}]'

open_xterm "PIN-TEST-LOCKED"
sleep 2

# Check drag inhibit via D-Bus
INHIBITED=$(cinnamon_eval "${FIND_APPLET_JS}
if (!_a) 'no applet';
else {
    let children = _a.manager_container.get_children();
    let result = 'not found';
    for (let i = 0; i < children.length; i++) {
        let btn = children[i]._delegate;
        if (btn && btn.metaWindow && btn.metaWindow.get_title() &&
            btn.metaWindow.get_title().indexOf('PIN-TEST-LOCKED') >= 0) {
            result = btn._draggable ? (btn._draggable.inhibit ? 'true' : 'false') : 'no draggable';
        }
    }
    result;
}
")

if [[ "$INHIBITED" == "true" ]]; then
    test_result "Drag is inhibited on pinned window" pass
else
    test_result "Drag is inhibited on pinned window" fail "inhibit=$INHIBITED"
fi

kill_test_windows

# ============================================================
# Scenario 6: App-only pin rule (no title filter)
# ============================================================
echo -e "\n${BOLD}Scenario 6: App-only pin rule (no title filter)${NC}"

set_pin_rules '[{"appId":"xterm.desktop","priority":0}]'

open_xterm "PIN-TEST-ANY1"
sleep 1
open_xterm "PIN-TEST-ANY2"
sleep 2

ORDER=$(get_child_order)
echo "  Button order: $ORDER"
PINNED_COUNT=$(check_pin_order "$ORDER" | python3 -c "import sys,json; print(json.loads(sys.stdin.read())['pinned_count'])")

if [[ "$PINNED_COUNT" == "2" ]]; then
    test_result "App-only rule pins all windows of that app" pass
else
    test_result "App-only rule pins all windows of that app" fail "pinned=$PINNED_COUNT"
fi

kill_test_windows

# ============================================================
# Cleanup
# ============================================================
echo -e "\n${CYAN}Cleaning up...${NC}"
clear_pin_rules
kill_test_windows

# Take final screenshot
run_display "xwd -root | convert xwd:- png:$SCREENSHOT_DIR/vm-pinning-final.png" 2>/dev/null || true

# --- Summary ---
echo -e "\n${BOLD}=== Results ===${NC}"
echo -e "  Total:    $TOTAL"
echo -e "  ${GREEN}Passed:  $PASSED${NC}"
if [[ $FAILED -gt 0 ]]; then
    echo -e "  ${RED}Failed:  $FAILED${NC}"
fi
if [[ $WARNINGS -gt 0 ]]; then
    echo -e "  ${YELLOW}Warnings: $WARNINGS${NC}"
fi

if [[ $FAILED -gt 0 ]]; then
    echo -e "\n${RED}FAILED${NC}"
    exit 1
else
    echo -e "\n${GREEN}ALL PASSED${NC}"
    exit 0
fi
