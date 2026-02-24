#!/bin/bash
# Smoke test: run Cinnamon with our applet in an isolated Xephyr display.
# This avoids crashing the production desktop if the applet has bugs.
#
# Prerequisites: sudo apt install xserver-xephyr
# Optional: sudo apt install xterm (for test windows)
#
# Usage: bash test/smoke-test.sh

set -euo pipefail

DISPLAY_NUM=":99"
LOG="/tmp/cinnamon-smoke-test.log"
APPLET_UUID="multirow-window-list@cinnamon"
APPLET_DIR="$HOME/.local/share/cinnamon/applets/$APPLET_UUID"
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PIDS=()

cleanup() {
    echo ""
    echo "Cleaning up..."
    # Restore original enabled-applets if we modified it
    if [ "${APPLET_ADDED:-false}" = "true" ] && [ -n "${ORIG_APPLETS:-}" ]; then
        dconf write /org/cinnamon/enabled-applets "$ORIG_APPLETS"
        echo "Restored enabled-applets setting"
    fi
    for pid in "${PIDS[@]}"; do
        kill "$pid" 2>/dev/null || true
    done
    wait 2>/dev/null || true
    echo "Done. Log at: $LOG"
}
trap cleanup EXIT

# Ensure symlink exists
if [ ! -L "$APPLET_DIR" ] && [ ! -d "$APPLET_DIR" ]; then
    ln -sfn "$SCRIPT_DIR" "$APPLET_DIR"
    echo "Created symlink: $APPLET_DIR -> $SCRIPT_DIR"
fi

# Check for Xephyr
if ! command -v Xephyr &>/dev/null; then
    echo "FAIL: Xephyr not found. Install with: sudo apt install xserver-xephyr"
    exit 1
fi

# Clean previous log
> "$LOG"

echo "=== Smoke Test: $APPLET_UUID ==="
echo ""

# Start Xephyr
echo "[1/5] Starting Xephyr on $DISPLAY_NUM ..."
Xephyr "$DISPLAY_NUM" -screen 1280x800 -ac 2>/dev/null &
PIDS+=($!)
sleep 1

# Enable our applet in the Xephyr session's dconf (uses the same dconf as host,
# so we save and restore the enabled-applets setting).
# Also disable the stock window-list to avoid role conflicts and conflated errors.
ORIG_APPLETS=$(dconf read /org/cinnamon/enabled-applets)
APPLET_ENTRY="'panel1:right:0:${APPLET_UUID}:99'"

# Remove stock window-list and add ours
NEW_APPLETS=$(echo "$ORIG_APPLETS" | sed "s/'[^']*window-list@cinnamon.org[^']*', *//g")
if ! echo "$NEW_APPLETS" | grep -q "$APPLET_UUID"; then
    NEW_APPLETS=$(echo "$NEW_APPLETS" | sed "s/]$/, ${APPLET_ENTRY}]/")
fi
dconf write /org/cinnamon/enabled-applets "$NEW_APPLETS"
APPLET_ADDED=true

# Start Cinnamon inside Xephyr
echo "[2/5] Starting Cinnamon inside Xephyr ..."
DISPLAY="$DISPLAY_NUM" cinnamon --replace > "$LOG" 2>&1 &
PIDS+=($!)
sleep 6

# Check for crashes
if ! kill -0 "${PIDS[1]}" 2>/dev/null; then
    echo "FAIL: Cinnamon process died!"
    echo "Last 20 lines of log:"
    tail -20 "$LOG"
    exit 1
fi

# Check applet loaded
if grep -q "Loaded applet $APPLET_UUID" "$LOG"; then
    echo "  OK: Applet loaded successfully"
else
    echo "  WARN: Applet load message not found in log"
    echo "  (applet might not be in enabled-applets for Xephyr session)"
fi

# Count critical errors
CRITS=0
if grep -c "Gjs-CRITICAL" "$LOG" >/dev/null 2>&1; then
    CRITS=$(grep -c "Gjs-CRITICAL" "$LOG")
fi
if [ "$CRITS" -gt 0 ]; then
    echo "  WARN: $CRITS Gjs-CRITICAL messages during startup"
else
    echo "  OK: No Gjs-CRITICAL messages during startup"
fi

# Check for segfaults
if grep -qi "segfault\|SIGSEGV\|abort" "$LOG" 2>/dev/null; then
    echo "FAIL: Crash detected in log!"
    tail -20 "$LOG"
    exit 1
fi

# Open some test windows (try xterm, fall back to bash in xdg-terminal or skip)
echo "[3/5] Opening test windows ..."
if command -v xterm &>/dev/null; then
    for i in $(seq 1 6); do
        DISPLAY="$DISPLAY_NUM" xterm -title "Test Window $i" -e "sleep 60" &
        PIDS+=($!)
    done
    sleep 3
else
    echo "  SKIP: xterm not installed (install with: sudo apt install xterm)"
    echo "  Continuing without test windows..."
fi

# Test Cinnamon restart (the doomloop scenario)
echo "[4/5] Testing cinnamon --replace (doomloop scenario) ..."
DISPLAY="$DISPLAY_NUM" cinnamon --replace >> "$LOG" 2>&1 &
NEW_PID=$!
PIDS+=($NEW_PID)
sleep 6

if ! kill -0 "$NEW_PID" 2>/dev/null; then
    echo "FAIL: Cinnamon crashed on restart!"
    echo "Last 30 lines of log:"
    tail -30 "$LOG"
    exit 1
fi

CRITS_AFTER=0
if grep -c "Gjs-CRITICAL" "$LOG" >/dev/null 2>&1; then
    CRITS_AFTER=$(grep -c "Gjs-CRITICAL" "$LOG")
fi

# Check if any errors reference our applet specifically (excluding info/load messages)
OUR_ERRORS=$(grep "multirow-window-list" "$LOG" 2>/dev/null | grep -v "Loaded applet\|Installing settings\|Settings successfully" | wc -l | tr -d ' ')

echo "[5/5] Results:"
echo "  Gjs-CRITICAL messages total: $CRITS_AFTER (Cinnamon baseline noise is ~100-400)"
echo "  Errors referencing our applet: $OUR_ERRORS"
if [ "$CRITS_AFTER" -gt 1000 ]; then
    echo "  FAIL: Extreme error count ($CRITS_AFTER) — likely doomloop"
    exit 1
elif [ "$OUR_ERRORS" -gt 0 ]; then
    echo "  WARN: Our applet generated errors (check $LOG)"
else
    echo "  OK: No errors from our applet"
fi

echo ""
echo "=== Smoke test PASSED ==="
echo "Xephyr window is still running for manual inspection."
echo "Press Ctrl+C to clean up and exit."
echo ""

# Wait for user to inspect
wait
