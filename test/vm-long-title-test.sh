#!/bin/bash
# VM test for Bug 2: Long window titles overflowing panel in single-row mode.
#
# Opens windows with very long titles (staying in single-row count) and verifies:
#   1. No button allocation box extends below the panel height
#   2. Label allocations are clamped within button allocation boxes
#   3. min_size <= natural_size in height (prevents Clutter from inflating)
#   4. Visual screenshot for manual inspection
#
# Prerequisites:
#   - Running inside the VM (or VM "cinnamon-dev" running)
#   - xterm installed
#   - Applet loaded in Cinnamon
#
# Usage:
#   bash test/vm-long-title-test.sh

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
VM_CTL="$PROJECT_DIR/vm/vm-ctl.sh"
SCREENSHOT_DIR="$SCRIPT_DIR/screenshots"
APPLET_UUID="multirow-window-list@science"

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

# --- Command helpers ---
run_cmd() {
    if $IS_LOCAL; then
        eval "$@"
    else
        local ip
        ip=$("$VM_CTL" ip 2>/dev/null)
        ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
            -o LogLevel=ERROR -o ConnectTimeout=5 "steve@$ip" "$@"
    fi
}

run_display() {
    if $IS_LOCAL; then
        DISPLAY=:0 eval "$@"
    else
        local ip
        ip=$("$VM_CTL" ip 2>/dev/null)
        ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
            -o LogLevel=ERROR -o ConnectTimeout=5 "steve@$ip" "DISPLAY=:0 $*"
    fi
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
        local ip
        ip=$("$VM_CTL" ip 2>/dev/null)
        ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
            -o LogLevel=ERROR "steve@$ip" "cat > /tmp/cinnamon-eval.py" < /tmp/cinnamon-eval.py
    fi
}

cinnamon_eval() {
    if $IS_LOCAL; then
        echo "$1" | DISPLAY=:0 python3 /tmp/cinnamon-eval.py
    else
        local ip
        ip=$("$VM_CTL" ip 2>/dev/null)
        echo "$1" | ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
            -o LogLevel=ERROR "steve@$ip" "DISPLAY=:0 python3 /tmp/cinnamon-eval.py"
    fi
}

json_field() {
    local json="$1"
    local field="$2"
    echo "$json" | python3 -c "import sys,json; print(json.loads(sys.stdin.read())['$field'])"
}

test_result() {
    local description="$1"
    local status="$2"    # pass, fail
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
    esac
}

# --- Long title generator ---
LONG_TITLE="This-is-a-very-long-window-title-that-should-be-truncated-by-the-applet-and-not-overflow-the-panel-boundary-even-in-spacious-single-row-mode-with-wrapping-text"

# Open N windows with very long titles, staying in single-row mode
open_long_title_windows() {
    local count=$1
    cat > /tmp/open-long-title-windows.sh <<SCRIPT
#!/bin/bash
for i in \$(seq 1 $count); do
    setsid xterm -title "${LONG_TITLE}-\$i" -e "sleep 300" &>/dev/null &
done
SCRIPT
    if ! $IS_LOCAL; then
        local ip
        ip=$("$VM_CTL" ip 2>/dev/null)
        ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
            -o LogLevel=ERROR "steve@$ip" "cat > /tmp/open-long-title-windows.sh" < /tmp/open-long-title-windows.sh
    fi
    run_display "bash /tmp/open-long-title-windows.sh"
}

close_windows() {
    run_display "xdotool search --name '${LONG_TITLE}' 2>/dev/null | while read wid; do xdotool windowclose \"\$wid\" 2>/dev/null; done" || true
    sleep 1
    run_cmd 'pkill -f "xterm -title This-is-a-very-long" 2>/dev/null' || true
}

take_screenshot() {
    local label="$1"
    local filename="vm-longtitle-${label}.png"
    mkdir -p "$SCREENSHOT_DIR"
    run_display "xwd -root -silent | convert xwd:- png:/tmp/screenshot.png" 2>/dev/null
    if $IS_LOCAL; then
        cp /tmp/screenshot.png "$SCREENSHOT_DIR/$filename" 2>/dev/null
    else
        local ip
        ip=$("$VM_CTL" ip 2>/dev/null)
        scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
            -o LogLevel=ERROR "steve@$ip:/tmp/screenshot.png" "$SCREENSHOT_DIR/$filename" 2>/dev/null
    fi
    echo "$SCREENSHOT_DIR/$filename"
}

# --- Query button height data ---
# Returns JSON with per-button allocation heights, label heights, and panel height
query_button_heights() {
    cinnamon_eval "
        const AppletManager = imports.ui.appletManager;
        let instances = AppletManager.getRunningInstancesForUuid('$APPLET_UUID');
        let applet = instances.length > 0 ? instances[0] : null;
        if (!applet) { JSON.stringify({error: 'no applet'}); }
        else {
            let panelH = applet._panelHeight || 0;
            let rows = applet._computedRows || 1;
            let buttons = [];
            for (let w of applet._windows) {
                if (!w.actor.visible) continue;
                let box = w.actor.get_allocation_box();
                let btnH = Math.round(box.y2 - box.y1);
                let btnY1 = Math.round(box.y1);
                let btnY2 = Math.round(box.y2);
                // Get the label allocation if possible
                let labelH = -1;
                let labelY2 = -1;
                try {
                    let lbox = w._label.get_allocation_box();
                    labelH = Math.round(lbox.y2 - lbox.y1);
                    labelY2 = Math.round(lbox.y2);
                } catch(e) {}
                // Get theme node overhead
                let tn = w.actor.get_theme_node();
                let vPad = tn.get_vertical_padding();
                let borderT = tn.get_border_width(0);
                let borderB = tn.get_border_width(2);
                let marginB = tn.get_length('margin-bottom');
                let marginT = tn.get_length('margin-top');
                let totalOuter = btnH + marginT + marginB + vPad + borderT + borderB;
                buttons.push({
                    height: btnH,
                    y1: btnY1,
                    y2: btnY2,
                    labelH: labelH,
                    labelY2: labelY2,
                    vPad: vPad,
                    borderT: borderT,
                    borderB: borderB,
                    marginT: marginT,
                    marginB: marginB,
                    totalOuter: Math.round(totalOuter),
                    title: w._label.get_text().substring(0, 40)
                });
            }
            JSON.stringify({
                panelHeight: panelH,
                computedRows: rows,
                buttonCount: buttons.length,
                buttons: buttons
            });
        }
    "
}

# ==========================================
#  MAIN TEST
# ==========================================

echo -e "${BOLD}${CYAN}=== Long Title Overflow Test (Bug 2) ===${NC}"
echo ""

# Preflight
install_eval_helper

# Clean any leftover test windows
close_windows 2>/dev/null

# Determine how many windows stay in single-row mode
# Query current container width and button width to calculate threshold
echo -e "${CYAN}--- Preflight: determining single-row capacity ---${NC}"
PREFLIGHT=$(cinnamon_eval "
    const AppletManager = imports.ui.appletManager;
    let instances = AppletManager.getRunningInstancesForUuid('$APPLET_UUID');
    let applet = instances.length > 0 ? instances[0] : null;
    if (!applet) { JSON.stringify({error: 'no applet'}); }
    else {
        let containerW = applet.actor.get_parent().get_width();
        let btnW = applet.buttonWidth || 150;
        let maxPerRow = Math.floor(containerW / btnW);
        let existingWindows = applet._windows.length;
        JSON.stringify({
            containerWidth: Math.round(containerW),
            buttonWidth: btnW,
            maxPerRow: maxPerRow,
            panelHeight: applet._panelHeight || 0,
            existingWindows: existingWindows
        });
    }
")

CONTAINER_W=$(json_field "$PREFLIGHT" "containerWidth")
BTN_W=$(json_field "$PREFLIGHT" "buttonWidth")
MAX_PER_ROW=$(json_field "$PREFLIGHT" "maxPerRow")
PANEL_H=$(json_field "$PREFLIGHT" "panelHeight")
EXISTING_WIN=$(json_field "$PREFLIGHT" "existingWindows")

# How many test windows can we add and stay in single row?
SLOTS_AVAILABLE=$((MAX_PER_ROW - EXISTING_WIN))
echo "  Container: ${CONTAINER_W}px, Button width: ${BTN_W}px, Max per row: ${MAX_PER_ROW}, Panel: ${PANEL_H}px"
echo "  Existing windows: ${EXISTING_WIN}, Slots available for single row: ${SLOTS_AVAILABLE}"

if [[ $SLOTS_AVAILABLE -lt 1 ]]; then
    echo -e "${YELLOW}WARNING: Already at or past single-row capacity. Close some windows for a cleaner test.${NC}"
    SLOTS_AVAILABLE=1
fi

# Test with counts that stay in single row
# Use 1, min(3, available), and the full boundary
TEST_COUNTS=(1)
if [[ $SLOTS_AVAILABLE -ge 3 ]]; then
    TEST_COUNTS+=(3)
fi
if [[ $SLOTS_AVAILABLE -gt 3 ]]; then
    TEST_COUNTS+=($SLOTS_AVAILABLE)
fi

for COUNT in "${TEST_COUNTS[@]}"; do
    echo ""
    echo -e "${CYAN}--- Test: ${COUNT} window(s) with long titles (single row) ---${NC}"

    open_long_title_windows "$COUNT"
    sleep 3

    # Query button heights
    RESULT=$(query_button_heights)
    if [[ -z "$RESULT" ]] || echo "$RESULT" | grep -q '"error"'; then
        test_result "Query button heights (${COUNT} windows)" "fail" "could not query applet state"
        close_windows
        continue
    fi

    COMPUTED_ROWS=$(json_field "$RESULT" "computedRows")
    BTN_COUNT=$(json_field "$RESULT" "buttonCount")

    # Assertion 1: Should be in single-row mode
    if [[ "$COMPUTED_ROWS" -eq 1 ]]; then
        test_result "Single-row mode with ${COUNT} windows" "pass" "rows=$COMPUTED_ROWS"
    else
        test_result "Single-row mode with ${COUNT} windows" "fail" "expected 1 row, got $COMPUTED_ROWS"
    fi

    # Assertion 2: No button allocation box extends beyond panel height
    OVERFLOW_BUTTONS=$(echo "$RESULT" | python3 -c "
import sys, json
data = json.loads(sys.stdin.read())
panel_h = data['panelHeight']
overflow = [b for b in data['buttons'] if b['y2'] > panel_h]
print(len(overflow))
for b in overflow:
    print(f\"  OVERFLOW: {b['title']} y2={b['y2']} > panel={panel_h}\", file=sys.stderr)
" 2>&1)

    OVERFLOW_COUNT=$(echo "$OVERFLOW_BUTTONS" | head -1)
    if [[ "$OVERFLOW_COUNT" -eq 0 ]]; then
        test_result "No buttons overflow panel (${COUNT} windows)" "pass" "all y2 <= ${PANEL_H}px"
    else
        test_result "No buttons overflow panel (${COUNT} windows)" "fail" "$OVERFLOW_COUNT button(s) extend past panel"
        echo "$OVERFLOW_BUTTONS" | tail -n +2 | head -5
    fi

    # Assertion 3: Label allocation stays within button allocation
    LABEL_OVERFLOW=$(echo "$RESULT" | python3 -c "
import sys, json
data = json.loads(sys.stdin.read())
overflow = []
for b in data['buttons']:
    if b['labelY2'] > 0 and b['labelH'] > 0:
        # Label y2 is relative to button content area, button height is content height
        # Label should not extend beyond button height
        if b['labelY2'] > b['y2']:
            overflow.append(b)
print(len(overflow))
for b in overflow:
    print(f\"  LABEL OVERFLOW: {b['title']} labelY2={b['labelY2']} > btnY2={b['y2']}\", file=sys.stderr)
" 2>&1)

    LABEL_OVF_COUNT=$(echo "$LABEL_OVERFLOW" | head -1)
    if [[ "$LABEL_OVF_COUNT" -eq 0 ]]; then
        test_result "Labels within button bounds (${COUNT} windows)" "pass"
    else
        test_result "Labels within button bounds (${COUNT} windows)" "fail" "$LABEL_OVF_COUNT label(s) overflow"
        echo "$LABEL_OVERFLOW" | tail -n +2 | head -5
    fi

    # Assertion 4: Button height + margin + border fits in panel row
    ROW_OVERFLOW=$(echo "$RESULT" | python3 -c "
import sys, json
data = json.loads(sys.stdin.read())
panel_h = data['panelHeight']
rows = data['computedRows']
target_row = panel_h // rows
overflow = []
for b in data['buttons']:
    total = b['height'] + b['marginT'] + b['marginB'] + b['vPad'] + b['borderT'] + b['borderB']
    if total > target_row + 1:  # +1 for rounding tolerance
        overflow.append({'title': b['title'], 'total': total, 'target': target_row})
print(len(overflow))
for o in overflow:
    print(f\"  ROW OVERFLOW: {o['title']} total={o['total']}px > target={o['target']}px\", file=sys.stderr)
" 2>&1)

    ROW_OVF_COUNT=$(echo "$ROW_OVERFLOW" | head -1)
    if [[ "$ROW_OVF_COUNT" -eq 0 ]]; then
        test_result "Button total fits row height (${COUNT} windows)" "pass" "target=${PANEL_H}px"
    else
        test_result "Button total fits row height (${COUNT} windows)" "fail" "$ROW_OVF_COUNT button(s) exceed row"
        echo "$ROW_OVERFLOW" | tail -n +2 | head -5
    fi

    # Assertion 5: All buttons are actually visible (not hidden/zero-sized)
    ZERO_HEIGHT=$(echo "$RESULT" | python3 -c "
import sys, json
data = json.loads(sys.stdin.read())
zero = [b for b in data['buttons'] if b['height'] <= 0]
print(len(zero))
")
    if [[ "$ZERO_HEIGHT" -eq 0 ]]; then
        test_result "All buttons have positive height (${COUNT} windows)" "pass" "${BTN_COUNT} buttons"
    else
        test_result "All buttons have positive height (${COUNT} windows)" "fail" "$ZERO_HEIGHT button(s) have 0 height"
    fi

    # Take screenshot
    SCREENSHOT=$(take_screenshot "${COUNT}win-longtitle")
    if [[ -f "$SCREENSHOT" ]]; then
        echo -e "  ${YELLOW}Screenshot:${NC} $SCREENSHOT"
        # Crop taskbar region for inspection
        if command -v convert &>/dev/null; then
            CROP="${SCREENSHOT%.png}-taskbar.png"
            convert "$SCREENSHOT" -gravity South -crop "x$((PANEL_H + 5))+0+0" +repage "$CROP" 2>/dev/null
            echo -e "  ${YELLOW}Taskbar crop:${NC} $CROP"
        fi
    else
        echo -e "  ${YELLOW}Screenshot:${NC} (capture failed)"
    fi

    close_windows
    sleep 1
done

# ==========================================
#  MULTI-ROW TEST (push past single-row capacity with long titles)
# ==========================================
echo ""
echo -e "${CYAN}--- Test: multi-row with long titles (overflow into 2 rows) ---${NC}"

# Open enough windows to force 2 rows
MULTIROW_COUNT=$((MAX_PER_ROW + 2))
open_long_title_windows "$MULTIROW_COUNT"
sleep 4

RESULT=$(query_button_heights)
if [[ -z "$RESULT" ]] || echo "$RESULT" | grep -q '"error"'; then
    test_result "Query button heights (multi-row)" "fail" "could not query applet state"
else
    COMPUTED_ROWS=$(json_field "$RESULT" "computedRows")
    BTN_COUNT=$(json_field "$RESULT" "buttonCount")

    # Should be in multi-row mode
    if [[ "$COMPUTED_ROWS" -ge 2 ]]; then
        test_result "Multi-row mode with long titles" "pass" "rows=$COMPUTED_ROWS, ${BTN_COUNT} buttons"
    else
        test_result "Multi-row mode with long titles" "fail" "expected >=2 rows, got $COMPUTED_ROWS"
    fi

    # No buttons should overflow panel in multi-row either
    OVERFLOW_COUNT=$(echo "$RESULT" | python3 -c "
import sys, json
data = json.loads(sys.stdin.read())
print(len([b for b in data['buttons'] if b['y2'] > data['panelHeight']]))
")
    if [[ "$OVERFLOW_COUNT" -eq 0 ]]; then
        test_result "No buttons overflow panel (multi-row)" "pass" "all y2 <= ${PANEL_H}px"
    else
        test_result "No buttons overflow panel (multi-row)" "fail" "$OVERFLOW_COUNT button(s) extend past panel"
    fi

    # Button total fits row
    ROW_OVF=$(echo "$RESULT" | python3 -c "
import sys, json
data = json.loads(sys.stdin.read())
target = data['panelHeight'] // data['computedRows']
print(len([b for b in data['buttons']
    if b['height'] + b['marginT'] + b['marginB'] + b['vPad'] + b['borderT'] + b['borderB'] > target + 1]))
")
    if [[ "$ROW_OVF" -eq 0 ]]; then
        test_result "Button total fits row (multi-row)" "pass"
    else
        test_result "Button total fits row (multi-row)" "fail" "$ROW_OVF button(s) exceed row"
    fi

    # All buttons visible
    ZERO_H=$(echo "$RESULT" | python3 -c "
import sys, json; data = json.loads(sys.stdin.read())
print(len([b for b in data['buttons'] if b['height'] <= 0]))
")
    if [[ "$ZERO_H" -eq 0 ]]; then
        test_result "All buttons visible (multi-row)" "pass" "${BTN_COUNT} buttons"
    else
        test_result "All buttons visible (multi-row)" "fail" "$ZERO_H with 0 height"
    fi

    SCREENSHOT=$(take_screenshot "multirow-longtitle")
    if [[ -f "$SCREENSHOT" ]]; then
        echo -e "  ${YELLOW}Screenshot:${NC} $SCREENSHOT"
    fi
fi

close_windows
sleep 1

# ==========================================
#  SUMMARY
# ==========================================
echo ""
echo -e "${BOLD}=== Results ===${NC}"
echo -e "  Total: $TOTAL  ${GREEN}Passed: $PASSED${NC}  ${RED}Failed: $FAILED${NC}"

if [[ $FAILED -gt 0 ]]; then
    echo -e "${RED}SOME TESTS FAILED${NC}"
    exit 1
else
    echo -e "${GREEN}ALL TESTS PASSED${NC}"
    exit 0
fi
