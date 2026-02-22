#!/bin/bash
# Uninstall multirow-window-list@cinnamon applet
#
# Safe to run from a TTY if Cinnamon has crashed.
# Removes the applet from dconf and deletes the symlink/directory.
#
# Usage: ./uninstall.sh

set -eo pipefail

UUID="multirow-window-list@cinnamon"
APPLET_DIR="$HOME/.local/share/cinnamon/applets/$UUID"

echo "Uninstalling $UUID..."

# 1. Remove from dconf enabled-applets list
CURRENT=$(dconf read /org/cinnamon/enabled-applets 2>/dev/null || echo "")
if echo "$CURRENT" | grep -q "$UUID"; then
    # Filter out any entry containing our UUID
    UPDATED=$(echo "$CURRENT" | python3 -c "
import sys, ast
raw = sys.stdin.read().strip()
entries = ast.literal_eval(raw)
filtered = [e for e in entries if '$UUID' not in e]
print(filtered)
")
    dconf write /org/cinnamon/enabled-applets "$UPDATED"
    echo "  Removed from enabled-applets"
else
    echo "  Not in enabled-applets (already disabled)"
fi

# 2. Remove applet files/symlink
if [ -L "$APPLET_DIR" ]; then
    rm "$APPLET_DIR"
    echo "  Removed symlink: $APPLET_DIR"
elif [ -d "$APPLET_DIR" ]; then
    rm -rf "$APPLET_DIR"
    echo "  Removed directory: $APPLET_DIR"
else
    echo "  No applet directory found (already removed)"
fi

echo ""
echo "Done. Restart Cinnamon to apply:"
echo "  - From desktop: Alt+F2 → r → Enter"
echo "  - From TTY:     DISPLAY=:0 cinnamon --replace &"
