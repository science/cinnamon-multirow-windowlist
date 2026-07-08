#!/bin/bash
# Restart Cinnamon to pick up applet code changes.
# Run from inside the VM (cinnamon-dev).
#
# Usage:
#   ./run.sh           # Restart Cinnamon, wait for it to be ready
#   ./run.sh --test    # Restart + run unit tests first
#   ./run.sh --watch   # Tail ~/.xsession-errors after restart

set -eo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Options ---
RUN_TESTS=false
WATCH_LOG=false
for arg in "$@"; do
    case "$arg" in
        --test)  RUN_TESTS=true ;;
        --watch) WATCH_LOG=true ;;
        --help|-h)
            echo "Usage: ./run.sh [--test] [--watch]"
            echo "  --test   Run unit tests (npm test) before restarting"
            echo "  --watch  Tail ~/.xsession-errors after restart"
            exit 0
            ;;
    esac
done

# --- Unit tests ---
if $RUN_TESTS; then
    echo -e "${CYAN}Running unit tests...${NC}"
    if ! npm test --prefix "$PROJECT_DIR" 2>&1 | tail -5; then
        echo -e "${RED}Unit tests failed — aborting restart${NC}"
        exit 1
    fi
    echo ""
fi

# --- Verify we're in the VM ---
# Guard against restarting Cinnamon on the host by accident. Accepts the
# legacy libvirt VM (cinnamon-dev) and Incus dev VMs (dev-1, dev-2, ...).
if [[ "$(hostname)" != "cinnamon-dev" ]] && [[ "$(hostname)" != dev-* ]]; then
    echo -e "${RED}ERROR: Not running inside a dev VM${NC}"
    echo "This script must be run from inside the VM (cinnamon-dev or dev-*)."
    exit 1
fi

# --- Check applet symlink ---
APPLET_LINK="$HOME/.local/share/cinnamon/applets/multirow-window-list@science"
if [[ ! -L "$APPLET_LINK" ]]; then
    echo -e "${RED}ERROR: Applet symlink missing at $APPLET_LINK${NC}"
    echo "Run ./install.sh to set it up."
    exit 1
fi

# --- Ensure cinnamon-eval.py exists ---
if [[ ! -f /tmp/cinnamon-eval.py ]]; then
    cat > /tmp/cinnamon-eval.py << 'EVAL_HELPER'
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
EVAL_HELPER
fi

# --- Restart Cinnamon ---
echo -e "${CYAN}Restarting Cinnamon...${NC}"

# Save current errors line count to show only new errors after restart
LOG_FILE="$HOME/.xsession-errors"
PREV_LINES=0
if [[ -f "$LOG_FILE" ]]; then
    PREV_LINES=$(wc -l < "$LOG_FILE")
fi

# Use nohup + setsid to fully detach cinnamon --replace from this shell
setsid cinnamon --replace &>/dev/null &
disown 2>/dev/null || true

# Wait for Cinnamon to be responsive (D-Bus eval works)
echo -n "  Waiting for Cinnamon..."
for i in $(seq 1 15); do
    sleep 1
    if echo 'global.log("run.sh health check")' | python3 /tmp/cinnamon-eval.py &>/dev/null 2>&1; then
        echo -e " ${GREEN}ready${NC} (${i}s)"
        break
    fi
    if [[ $i -eq 15 ]]; then
        echo -e " ${RED}timeout after 15s${NC}"
        echo "Cinnamon may have crashed. Check ~/.xsession-errors"
        exit 1
    fi
    echo -n "."
done

# --- Check for applet errors ---
if [[ -f "$LOG_FILE" ]]; then
    CURR_LINES=$(wc -l < "$LOG_FILE")
    NEW_LINES=$((CURR_LINES - PREV_LINES))
    if [[ $NEW_LINES -gt 0 ]]; then
        APPLET_ERRORS=$(tail -n "$NEW_LINES" "$LOG_FILE" | grep -ci "multirow\|window.list\|applet" || true)
        if [[ $APPLET_ERRORS -gt 0 ]]; then
            echo -e "${RED}  WARNING: $APPLET_ERRORS applet-related log lines since restart${NC}"
            tail -n "$NEW_LINES" "$LOG_FILE" | grep -i "multirow\|window.list\|applet" | head -5
        else
            echo -e "  ${GREEN}No applet errors in log${NC}"
        fi
    fi
fi

echo -e "${GREEN}Done.${NC} Cinnamon restarted with latest applet code."

# --- Watch log ---
if $WATCH_LOG; then
    echo -e "\n${CYAN}Tailing ~/.xsession-errors (Ctrl+C to stop)...${NC}\n"
    tail -f "$LOG_FILE"
fi
