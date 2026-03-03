#!/bin/bash
# E2E test for window grouping by application.
#
# Reproduces a bug where newly opened windows of certain applications
# are placed at the end of the window list instead of being grouped
# next to existing windows of the same app.
#
# Prerequisites:
#   - VM "cinnamon-dev" running (./vm/vm-ctl.sh start)
#   - xterm, xclock, xeyes installed (sudo apt install x11-apps xterm)
#   - Applet loaded with group-windows enabled
#
# Usage:
#   ./test/vm-grouping-test.sh              # Run all scenarios
#   ./test/vm-grouping-test.sh --revert     # Revert to clean-baseline first
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

# --- SSH helpers ---
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

vm_run() {
    vm_ssh "DISPLAY=:0 $*"
}

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
    if val.startswith('"') and val.endswith('"'):
        val = val[1:-1]
    val = val.replace('\\"', '"').replace('\\\\', '\\')
    print(val)
    sys.exit(0 if success else 1)
else:
    print("PARSE_ERROR: " + output, file=sys.stderr)
    sys.exit(1)
EVAL_HELPER
}

cinnamon_eval() {
    echo "$1" | vm_ssh "DISPLAY=:0 python3 /tmp/cinnamon-eval.py"
}

# --- JSON helpers ---
json_field() {
    echo "$1" | python3 -c "import sys,json; print(json.loads(sys.stdin.read())['$2'])"
}

json_array_len() {
    echo "$1" | python3 -c "import sys,json; print(len(json.loads(sys.stdin.read())))"
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

# --- Query container child order ---
# Returns JSON array of {appId, title, wmClass} for each button in order.
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
        let wmClass = btn.metaWindow.get_wm_class() || 'none';
        let title = (btn.metaWindow.get_title() || '').substring(0,40);
        r.push({appId: appId, wmClass: wmClass, title: title});
    }
    JSON.stringify(r);
}
"
}

# --- Check if windows of the same app are contiguous ---
# Takes JSON child order, returns JSON: {grouped: true/false, violations: [...]}
check_grouping() {
    python3 -c "
import sys, json
order = json.loads(sys.stdin.read())
last_seen = {}
violations = []
for i, entry in enumerate(order):
    aid = entry['appId']
    if aid == 'NULL' or aid.startswith('window:'):
        continue
    if aid in last_seen:
        gap_apps = set()
        for j in range(last_seen[aid] + 1, i):
            other = order[j]['appId']
            if other != aid and not other.startswith('window:') and other != 'NULL':
                gap_apps.add(other)
        if gap_apps:
            violations.append({
                'appId': aid,
                'index': i,
                'lastIndex': last_seen[aid],
                'title': entry['title'],
                'gapApps': list(gap_apps)
            })
    last_seen[aid] = i
result = {'grouped': len(violations) == 0, 'violations': violations}
print(json.dumps(result))
"
}


# --- Window management ---
open_app_windows() {
    local app="$1"
    local count="$2"
    local title_prefix="${3:-$app}"
    vm_ssh "cat > /tmp/open-${app}-windows.sh" <<REMOTE_SCRIPT
#!/bin/bash
for i in \$(seq 1 $count); do
    setsid $app -title "${title_prefix}-\$i" &>/dev/null &
    sleep 0.2
done
REMOTE_SCRIPT
    vm_run "bash /tmp/open-${app}-windows.sh"
}

# Open xterm windows with a specific title prefix
open_xterms() {
    local count="$1"
    local prefix="${2:-XtermGroup}"
    vm_ssh "cat > /tmp/open-xterms.sh" <<REMOTE_SCRIPT
#!/bin/bash
for i in \$(seq 1 $count); do
    setsid xterm -title "${prefix}-\$i" -e "sleep 600" &>/dev/null &
    sleep 0.2
done
REMOTE_SCRIPT
    vm_run "bash /tmp/open-xterms.sh"
}

# Open xclock windows
open_xclocks() {
    local count="$1"
    for i in $(seq 1 "$count"); do
        vm_run "setsid xclock -title XClock-$i &>/dev/null &"
        sleep 0.2
    done
}

# Open xeyes windows
open_xeyes() {
    local count="$1"
    for i in $(seq 1 "$count"); do
        vm_run "setsid xeyes -title XEyes-$i &>/dev/null &"
        sleep 0.2
    done
}

close_all_test_windows() {
    vm_ssh "pkill -f 'sleep 600' 2>/dev/null; pkill xclock 2>/dev/null; pkill xeyes 2>/dev/null; pkill xterm 2>/dev/null; pkill gedit 2>/dev/null" || true
    sleep 1
}

# --- Screenshot ---
screenshot() {
    local label="${1:-grouping}"
    mkdir -p "$SCREENSHOT_DIR"
    vm_run "xwd -root -silent" > /tmp/vm-screenshot.xwd 2>/dev/null
    convert xwd:/tmp/vm-screenshot.xwd "$SCREENSHOT_DIR/vm-grouping-${label}.png" 2>/dev/null || true
}

# ============================================================
#   PREFLIGHT
# ============================================================

# Parse args
DO_REVERT=false
for arg in "$@"; do
    case "$arg" in
        --revert) DO_REVERT=true ;;
    esac
done

echo -e "${BOLD}══════════════════════════════════════════════${NC}"
echo -e "${BOLD}  Window Grouping E2E Test${NC}"
echo -e "${BOLD}══════════════════════════════════════════════${NC}"
echo

if $DO_REVERT; then
    echo -e "${CYAN}Reverting to clean-baseline...${NC}"
    "$VM_CTL" revert clean-baseline 2>&1 | head -2
    "$VM_CTL" start 2>&1 | head -1 || true
    echo "Waiting for VM boot..."
    for i in $(seq 1 30); do
        if vm_ssh "echo ok" 2>/dev/null | grep -q ok; then break; fi
        sleep 2
    done
fi

echo -e "${BOLD}Pre-flight checks${NC}"

# VM running?
if "$VM_CTL" status 2>/dev/null | grep -q running; then
    test_result "VM is running" "pass"
else
    echo -e "  ${RED}FATAL: VM not running${NC}"
    exit 1
fi

# SSH works?
if vm_ssh "echo ok" 2>/dev/null | grep -q ok; then
    test_result "SSH to VM" "pass"
else
    echo -e "  ${RED}FATAL: SSH failed${NC}"
    exit 1
fi

# Required tools
for tool in xterm xclock xeyes; do
    if vm_ssh "which $tool" &>/dev/null; then
        test_result "$tool available" "pass"
    else
        echo -e "  ${RED}FATAL: $tool not installed in VM${NC}"
        echo "  Install: $VM_CTL ssh 'sudo apt install -y xterm x11-apps'"
        exit 1
    fi
done

# D-Bus eval helper
install_eval_helper
if cinnamon_eval '"hello"' 2>/dev/null | grep -q hello; then
    test_result "D-Bus eval helper" "pass"
else
    echo -e "  ${RED}FATAL: D-Bus eval not working${NC}"
    exit 1
fi

# Applet loaded?
APPLET_CHECK=$(cinnamon_eval "${FIND_APPLET_JS} _a ? 'found' : 'missing'" 2>/dev/null || echo "error")
if [[ "$APPLET_CHECK" == "found" ]]; then
    test_result "Applet loaded in panel" "pass"
else
    echo -e "  ${RED}FATAL: Applet not found in panel${NC}"
    exit 1
fi

# groupWindows enabled?
GROUP_CHECK=$(cinnamon_eval "${FIND_APPLET_JS} _a ? String(_a.groupWindows) : 'missing'" 2>/dev/null || echo "error")
if [[ "$GROUP_CHECK" == "true" ]]; then
    test_result "groupWindows enabled" "pass"
else
    echo -e "  ${YELLOW}WARN: groupWindows=$GROUP_CHECK — enabling it${NC}"
    # Force-enable for this test
    cinnamon_eval "${FIND_APPLET_JS} if(_a) _a.groupWindows = true; 'ok'" >/dev/null 2>&1
fi

# Clean slate
close_all_test_windows
sleep 1
echo

# ============================================================
#   SCENARIO 1: Fresh grouping (no restart)
#   Open A, A, B, B, then open A — new A should be at index 2
# ============================================================

echo -e "${BOLD}Scenario 1: Fresh grouping — interleaved apps${NC}"
echo -e "  ${CYAN}Opening 3 xterm, 3 xclock, then 1 more xterm...${NC}"

open_xterms 3 "GroupA"
sleep 2
open_xclocks 3
sleep 2

# Check order before adding another xterm
order_before=$(get_child_order)
echo -e "  ${CYAN}Order before new xterm:${NC}"
echo "$order_before" | python3 -c "
import sys, json
order = json.loads(sys.stdin.read())
for i, e in enumerate(order):
    print(f'    {i}: {e[\"appId\"]} | {e[\"wmClass\"]} | {e[\"title\"]}')
"

# Now open 1 more xterm — it should appear next to existing xterms
open_xterms 1 "NewXterm"
sleep 2

order_after=$(get_child_order)
echo -e "  ${CYAN}Order after new xterm:${NC}"
echo "$order_after" | python3 -c "
import sys, json
order = json.loads(sys.stdin.read())
for i, e in enumerate(order):
    print(f'    {i}: {e[\"appId\"]} | {e[\"wmClass\"]} | {e[\"title\"]}')
"

# Assert grouping is contiguous
grouping=$(echo "$order_after" | check_grouping)
is_grouped=$(json_field "$grouping" "grouped")
if [[ "$is_grouped" == "True" ]]; then
    test_result "Scenario 1: All apps contiguously grouped" "pass"
else
    violations=$(echo "$grouping" | python3 -c "
import sys, json
data = json.loads(sys.stdin.read())
for v in data['violations']:
    print(f\"  {v['appId']}: index {v['index']} separated from {v['lastIndex']} by {v['gapApps']}\")
")
    test_result "Scenario 1: Apps NOT contiguously grouped" "fail" "$violations"
fi

screenshot "s1-fresh"
close_all_test_windows
sleep 1
echo

# ============================================================
#   SCENARIO 2: Grouping after Cinnamon restart
#   Open A, A, B, B — restart Cinnamon — check order preserved
# ============================================================

echo -e "${BOLD}Scenario 2: Grouping survives Cinnamon restart${NC}"
echo -e "  ${CYAN}Opening 3 xterm, 3 xclock...${NC}"

open_xterms 3 "RestartA"
sleep 2
open_xclocks 3
sleep 2

order_pre_restart=$(get_child_order)
echo -e "  ${CYAN}Order before restart:${NC}"
echo "$order_pre_restart" | python3 -c "
import sys, json
order = json.loads(sys.stdin.read())
for i, e in enumerate(order):
    print(f'    {i}: {e[\"appId\"]} | {e[\"wmClass\"]} | {e[\"title\"]}')
"

# Restart Cinnamon
echo -e "  ${CYAN}Restarting Cinnamon...${NC}"
vm_ssh "DISPLAY=:0 cinnamon --replace &>/dev/null &"
sleep 6

order_post_restart=$(get_child_order)
echo -e "  ${CYAN}Order after restart:${NC}"
echo "$order_post_restart" | python3 -c "
import sys, json
order = json.loads(sys.stdin.read())
for i, e in enumerate(order):
    print(f'    {i}: {e[\"appId\"]} | {e[\"wmClass\"]} | {e[\"title\"]}')
"

grouping=$(echo "$order_post_restart" | check_grouping)
is_grouped=$(json_field "$grouping" "grouped")
if [[ "$is_grouped" == "True" ]]; then
    test_result "Scenario 2: Grouping intact after restart" "pass"
else
    violations=$(echo "$grouping" | python3 -c "
import sys, json
data = json.loads(sys.stdin.read())
for v in data['violations']:
    print(f\"  {v['appId']}: index {v['index']} separated from {v['lastIndex']} by {v['gapApps']}\")
")
    test_result "Scenario 2: Grouping BROKEN after restart" "fail" "$violations"
fi

screenshot "s2-post-restart"

# Now open 1 more xterm — should still group correctly
echo -e "  ${CYAN}Opening 1 more xterm after restart...${NC}"
open_xterms 1 "PostRestart"
sleep 2

order_post_new=$(get_child_order)
echo -e "  ${CYAN}Order after new window:${NC}"
echo "$order_post_new" | python3 -c "
import sys, json
order = json.loads(sys.stdin.read())
for i, e in enumerate(order):
    print(f'    {i}: {e[\"appId\"]} | {e[\"wmClass\"]} | {e[\"title\"]}')
"

grouping=$(echo "$order_post_new" | check_grouping)
is_grouped=$(json_field "$grouping" "grouped")
if [[ "$is_grouped" == "True" ]]; then
    test_result "Scenario 2: New window grouped after restart" "pass"
else
    violations=$(echo "$grouping" | python3 -c "
import sys, json
data = json.loads(sys.stdin.read())
for v in data['violations']:
    print(f\"  {v['appId']}: index {v['index']} separated from {v['lastIndex']} by {v['gapApps']}\")
")
    test_result "Scenario 2: New window NOT grouped after restart" "fail" "$violations"
fi

screenshot "s2-post-restart-new"
close_all_test_windows
sleep 1
echo

# ============================================================
#   SCENARIO 3: Three different apps, then add one of each
#   A, A, B, B, C, C → add A → add C → add B
#   All should remain contiguous
# ============================================================

echo -e "${BOLD}Scenario 3: Three apps — add one of each${NC}"
echo -e "  ${CYAN}Opening 2 xterm, 2 xclock, 2 xeyes...${NC}"

open_xterms 2 "ThreeA"
sleep 1
open_xclocks 2
sleep 1
open_xeyes 2
sleep 2

echo -e "  ${CYAN}Adding 1 xterm, 1 xeyes, 1 xclock...${NC}"
open_xterms 1 "ThreeA-new"
sleep 1
open_xeyes 1
sleep 1
open_xclocks 1
sleep 2

order=$(get_child_order)
echo -e "  ${CYAN}Final order:${NC}"
echo "$order" | python3 -c "
import sys, json
order = json.loads(sys.stdin.read())
for i, e in enumerate(order):
    print(f'    {i}: {e[\"appId\"]} | {e[\"wmClass\"]} | {e[\"title\"]}')
"

grouping=$(echo "$order" | check_grouping)
is_grouped=$(json_field "$grouping" "grouped")
if [[ "$is_grouped" == "True" ]]; then
    test_result "Scenario 3: Three apps all contiguous" "pass"
else
    violations=$(echo "$grouping" | python3 -c "
import sys, json
data = json.loads(sys.stdin.read())
for v in data['violations']:
    print(f\"  {v['appId']}: index {v['index']} separated from {v['lastIndex']} by {v['gapApps']}\")
")
    test_result "Scenario 3: Apps NOT contiguous" "fail" "$violations"
fi

screenshot "s3-three-apps"
close_all_test_windows
sleep 1
echo

# ============================================================
#   SCENARIO 4: App tracker race — rapid window creation
#   Open 5 xterms rapidly, then 5 xclocks rapidly, then 3 xterms
#   Tests whether the 20ms async delay is sufficient
# ============================================================

echo -e "${BOLD}Scenario 4: Rapid window creation (app tracker race)${NC}"
echo -e "  ${CYAN}Rapidly opening 5 xterm, 5 xclock, then 3 xterm...${NC}"

# Open rapidly (minimal delay)
vm_ssh "cat > /tmp/rapid-open.sh" << 'REMOTE_SCRIPT'
#!/bin/bash
for i in $(seq 1 5); do
    setsid xterm -title "RapidA-$i" -e "sleep 600" &>/dev/null &
done
sleep 0.5
for i in $(seq 1 5); do
    setsid xclock -title "RapidB-$i" &>/dev/null &
done
sleep 0.5
for i in $(seq 1 3); do
    setsid xterm -title "RapidA-late-$i" -e "sleep 600" &>/dev/null &
done
REMOTE_SCRIPT
vm_run "bash /tmp/rapid-open.sh"
sleep 4

order=$(get_child_order)
echo -e "  ${CYAN}Final order:${NC}"
echo "$order" | python3 -c "
import sys, json
order = json.loads(sys.stdin.read())
for i, e in enumerate(order):
    print(f'    {i}: {e[\"appId\"]} | {e[\"wmClass\"]} | {e[\"title\"]}')
"

grouping=$(echo "$order" | check_grouping)
is_grouped=$(json_field "$grouping" "grouped")
if [[ "$is_grouped" == "True" ]]; then
    test_result "Scenario 4: Rapid creation — all grouped" "pass"
else
    violations=$(echo "$grouping" | python3 -c "
import sys, json
data = json.loads(sys.stdin.read())
for v in data['violations']:
    print(f\"  {v['appId']}: index {v['index']} separated from {v['lastIndex']} by {v['gapApps']}\")
")
    test_result "Scenario 4: Rapid creation — grouping BROKEN" "fail" "$violations"
fi

screenshot "s4-rapid"
close_all_test_windows
sleep 1
echo

# ============================================================
#   SCENARIO 5: Stale saved order corrupts grouping after restart
#   Reproduces the host Firefox bug using xterm + gedit (both
#   have real .desktop files, so check_grouping validates them).
#   1. Clean slate: kill all test windows
#   2. Open 3 xterm, 3 gedit (grouped: [xterm x3, gedit x3])
#   3. Scramble via D-Bus: interleave xterm and gedit
#   4. Save the scrambled order
#   5. Restart Cinnamon → _applySavedOrder restores scramble
#   6. Open new xterm → should group with xterms, not at end
# ============================================================

echo -e "${BOLD}Scenario 5: Stale saved order corrupts grouping${NC}"
echo -e "  ${CYAN}Opening 3 xterm, 3 gedit (both have .desktop IDs)...${NC}"

open_xterms 3 "StaleA"
sleep 2
for i in 1 2 3; do
    vm_run "setsid gedit --new-window &>/dev/null &"
    sleep 0.5
done
sleep 3

order_clean=$(get_child_order)
echo -e "  ${CYAN}Clean grouped order:${NC}"
echo "$order_clean" | python3 -c "
import sys, json
order = json.loads(sys.stdin.read())
for i, e in enumerate(order):
    print(f'    {i}: {e[\"appId\"]} | {e[\"wmClass\"]} | {e[\"title\"]}')
"

# Scramble: interleave xterm and gedit children via D-Bus.
# Find indices by appId and interleave them.
echo -e "  ${CYAN}Scrambling container order via D-Bus (interleave xterm/gedit)...${NC}"
cinnamon_eval "${FIND_APPLET_JS}
if (_a) {
    let tracker = imports.gi.Cinnamon.WindowTracker.get_default();
    let children = _a.manager_container.get_children();
    // Collect xterm and gedit actors
    let xterms = [];
    let gedits = [];
    let others = [];
    for (let i = 0; i < children.length; i++) {
        let btn = children[i]._delegate;
        if (!btn || !btn.metaWindow) { others.push(children[i]); continue; }
        let app = tracker.get_window_app(btn.metaWindow);
        let appId = app ? app.get_id() : '';
        if (appId.indexOf('xterm') >= 0) xterms.push(children[i]);
        else if (appId.indexOf('gedit') >= 0) gedits.push(children[i]);
        else others.push(children[i]);
    }
    // Interleave: xterm, gedit, xterm, gedit, xterm, gedit, others...
    let interleaved = [];
    let maxLen = Math.max(xterms.length, gedits.length);
    for (let i = 0; i < maxLen; i++) {
        if (i < xterms.length) interleaved.push(xterms[i]);
        if (i < gedits.length) interleaved.push(gedits[i]);
    }
    interleaved = interleaved.concat(others);
    // Apply new order
    for (let i = 0; i < interleaved.length; i++) {
        _a.manager_container.set_child_at_index(interleaved[i], i);
    }
}
'scrambled'
" >/dev/null 2>&1

# Force save the scrambled order
cinnamon_eval "${FIND_APPLET_JS}
if (_a) {
    _a.refreshing = false;
    let new_order = [];
    let actors = _a.manager_container.get_children();
    for (let i = 0; i < actors.length; i++) {
        new_order.push(actors[i]._delegate.xid);
    }
    _a.lastWindowOrder = new_order.join('::');
}
'saved'
" >/dev/null 2>&1

order_scrambled=$(get_child_order)
echo -e "  ${CYAN}Scrambled order (saved to settings):${NC}"
echo "$order_scrambled" | python3 -c "
import sys, json
order = json.loads(sys.stdin.read())
for i, e in enumerate(order):
    print(f'    {i}: {e[\"appId\"]} | {e[\"wmClass\"]} | {e[\"title\"]}')
"

# Verify it's actually scrambled (xterm and gedit interleaved)
scramble_check=$(echo "$order_scrambled" | check_grouping)
scramble_grouped=$(json_field "$scramble_check" "grouped")
if [[ "$scramble_grouped" == "False" ]]; then
    test_result "Scenario 5 setup: Order successfully scrambled" "pass"
else
    test_result "Scenario 5 setup: Scramble didn't break grouping" "warn" "test may be inconclusive"
fi

# Restart Cinnamon — _applySavedOrder will restore the scrambled order
echo -e "  ${CYAN}Restarting Cinnamon (will restore stale saved order)...${NC}"
vm_ssh "DISPLAY=:0 cinnamon --replace &>/dev/null &"
sleep 6

order_post=$(get_child_order)
echo -e "  ${CYAN}Order after restart (should be re-grouped if fix works):${NC}"
echo "$order_post" | python3 -c "
import sys, json
order = json.loads(sys.stdin.read())
for i, e in enumerate(order):
    print(f'    {i}: {e[\"appId\"]} | {e[\"wmClass\"]} | {e[\"title\"]}')
"

grouping=$(echo "$order_post" | check_grouping)
is_grouped=$(json_field "$grouping" "grouped")
if [[ "$is_grouped" == "True" ]]; then
    test_result "Scenario 5: Grouping restored after stale-order restart" "pass"
else
    violations=$(echo "$grouping" | python3 -c "
import sys, json
data = json.loads(sys.stdin.read())
for v in data['violations']:
    print(f\"  {v['appId']}: index {v['index']} separated from {v['lastIndex']} by {v['gapApps']}\")
")
    test_result "Scenario 5: Stale order CORRUPTED grouping after restart" "fail" "$violations"
fi

# Now open a new xterm — should group with xterms, not at end
echo -e "  ${CYAN}Opening 1 new xterm after stale-order restart...${NC}"
open_xterms 1 "StaleA-new"
sleep 2

order_new=$(get_child_order)
echo -e "  ${CYAN}Order after new window:${NC}"
echo "$order_new" | python3 -c "
import sys, json
order = json.loads(sys.stdin.read())
for i, e in enumerate(order):
    print(f'    {i}: {e[\"appId\"]} | {e[\"wmClass\"]} | {e[\"title\"]}')
"

grouping=$(echo "$order_new" | check_grouping)
is_grouped=$(json_field "$grouping" "grouped")
if [[ "$is_grouped" == "True" ]]; then
    test_result "Scenario 5: New window grouped after stale-order restart" "pass"
else
    violations=$(echo "$grouping" | python3 -c "
import sys, json
data = json.loads(sys.stdin.read())
for v in data['violations']:
    print(f\"  {v['appId']}: index {v['index']} separated from {v['lastIndex']} by {v['gapApps']}\")
")
    test_result "Scenario 5: New window NOT grouped after stale-order restart" "fail" "$violations"
fi

screenshot "s5-stale-order"
close_all_test_windows
vm_ssh "pkill gedit" 2>/dev/null || true
sleep 1
echo

# ============================================================
#   SUMMARY
# ============================================================

echo -e "${BOLD}══════════════════════════════════════════════${NC}"
echo -e "${BOLD}  Summary${NC}"
echo -e "${BOLD}══════════════════════════════════════════════${NC}"
echo -e "  Total:    $TOTAL"
echo -e "  ${GREEN}Passed:   $PASSED${NC}"
if [[ $FAILED -gt 0 ]]; then
    echo -e "  ${RED}Failed:   $FAILED${NC}"
fi
if [[ $WARNINGS -gt 0 ]]; then
    echo -e "  ${YELLOW}Warnings: $WARNINGS${NC}"
fi
echo

if [[ $FAILED -gt 0 ]]; then
    echo -e "${RED}RESULT: FAIL${NC}"
    exit 1
else
    echo -e "${GREEN}RESULT: PASS${NC}"
    exit 0
fi
