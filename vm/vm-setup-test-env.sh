#!/bin/bash
# Set up the cinnamon-dev VM for systray-overflow applet testing.
#
# This script:
#   1. Verifies VM is running and SSH works
#   2. Installs required packages (tray apps, guest agent, xdotool)
#   3. Installs our applet (symlink from virtio-fs mount)
#   4. Swaps stock systray/xapp-status for our applet in dconf
#   5. Starts tray apps for icon variety
#   6. Restarts Cinnamon to load everything
#   7. Optionally takes a snapshot
#
# Prerequisites:
#   - VM "cinnamon-dev" running (./vm/vm-ctl.sh start)
#   - Host ~/dev mounted at /mnt/host-dev/ in VM (virtio-fs)
#
# Usage:
#   ./vm/vm-setup-test-env.sh              # Set up test environment
#   ./vm/vm-setup-test-env.sh --snapshot   # Set up + take snapshot

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
VM_CTL="$SCRIPT_DIR/vm-ctl.sh"
APPLET_UUID="systray-overflow@cinnamon"
HOST_DEV_MOUNT="/mnt/host-dev/cinnamon-systray-overflow"

# Packages to install for tray icon variety
TRAY_APPS=(pasystray redshift-gtk flameshot)
VM_PACKAGES=(qemu-guest-agent xdotool "${TRAY_APPS[@]}")

# Stock applets to remove (conflict with ours)
STOCK_REMOVE=("systray@cinnamon.org" "xapp-status@cinnamon.org")

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# --- Parse args ---
DO_SNAPSHOT=false
for arg in "$@"; do
    case "$arg" in
        --snapshot) DO_SNAPSHOT=true ;;
        --help|-h)
            echo "Usage: $0 [--snapshot]"
            echo "  --snapshot  Take a snapshot after setup"
            exit 0 ;;
    esac
done

echo ""
echo -e "${BOLD}═══════════════════════════════════════════════${NC}"
echo -e "${BOLD}  VM Test Environment Setup — $APPLET_UUID${NC}"
echo -e "${BOLD}═══════════════════════════════════════════════${NC}"
echo ""

# --- Step 1: Verify VM ---
echo -e "${BOLD}[1/7] Checking VM...${NC}"

state=$("$VM_CTL" status 2>/dev/null | grep -o 'running' || true)
if [[ "$state" != "running" ]]; then
    echo -e "  ${RED}VM is not running. Starting...${NC}"
    "$VM_CTL" start
    sleep 10
fi

ip=$("$VM_CTL" ip 2>/dev/null || true)
if [[ -z "$ip" ]]; then
    echo -e "  Waiting for IP..."
    for i in $(seq 1 30); do
        ip=$("$VM_CTL" ip 2>/dev/null || true)
        [[ -n "$ip" ]] && break
        sleep 2
    done
fi
if [[ -z "$ip" ]]; then
    echo -e "  ${RED}FATAL: Cannot get VM IP after 60s${NC}"
    exit 1
fi

SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=5"
vm_ssh() { ssh $SSH_OPTS "steve@$ip" "$@"; }

hostname=$(vm_ssh "hostname" 2>/dev/null || true)
if [[ -z "$hostname" ]]; then
    echo -e "  ${RED}FATAL: Cannot SSH to VM at $ip${NC}"
    exit 1
fi
echo -e "  ${GREEN}VM running: $hostname ($ip)${NC}"

# Check host-dev mount
if ! vm_ssh "test -d $HOST_DEV_MOUNT" 2>/dev/null; then
    echo -e "  ${RED}FATAL: Host dev mount not found at $HOST_DEV_MOUNT${NC}"
    echo "  Is virtio-fs configured in the VM?"
    exit 1
fi
echo -e "  ${GREEN}Host dev mount: OK${NC}"

# --- Step 2: Install packages ---
echo ""
echo -e "${BOLD}[2/7] Installing packages...${NC}"

# Check which packages need installing
to_install=()
for pkg in "${VM_PACKAGES[@]}"; do
    if ! vm_ssh "dpkg -l $pkg 2>/dev/null | grep -q '^ii'" 2>/dev/null; then
        to_install+=("$pkg")
    fi
done

if [[ ${#to_install[@]} -gt 0 ]]; then
    echo "  Installing: ${to_install[*]}"
    vm_ssh "sudo DEBIAN_FRONTEND=noninteractive apt-get update -qq && sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq ${to_install[*]}" 2>&1 | tail -3
    echo -e "  ${GREEN}Packages installed${NC}"
else
    echo -e "  ${GREEN}All packages already installed${NC}"
fi

# --- Step 3: Enable guest agent ---
echo ""
echo -e "${BOLD}[3/7] Configuring guest agent...${NC}"

ga_status=$(vm_ssh "systemctl is-active qemu-guest-agent 2>/dev/null" || echo "inactive")
if [[ "$ga_status" != "active" ]]; then
    # Check for virtio channel
    if vm_ssh "test -e /dev/virtio-ports/org.qemu.guest_agent.0" 2>/dev/null; then
        vm_ssh "sudo systemctl start qemu-guest-agent" 2>/dev/null
        echo -e "  ${GREEN}Guest agent started${NC}"
    else
        echo -e "  ${CYAN}Guest agent channel not present — add with:${NC}"
        echo '  virsh attach-device cinnamon-dev --config --live /dev/stdin <<EOF'
        echo '  <channel type="unix"><target type="virtio" name="org.qemu.guest_agent.0"/></channel>'
        echo '  EOF'
    fi
else
    echo -e "  ${GREEN}Guest agent already running${NC}"
fi

# --- Step 4: Install applet ---
echo ""
echo -e "${BOLD}[4/7] Installing applet...${NC}"

applet_dir="\$HOME/.local/share/cinnamon/applets/$APPLET_UUID"
if vm_ssh "test -L $applet_dir" 2>/dev/null; then
    echo -e "  ${GREEN}Applet symlink already exists${NC}"
else
    vm_ssh "cd $HOST_DEV_MOUNT && bash install.sh" 2>&1 | grep -v '^$'
    echo -e "  ${GREEN}Applet installed${NC}"
fi

# --- Step 5: Configure panel ---
echo ""
echo -e "${BOLD}[5/7] Configuring panel applets...${NC}"

current=$(vm_ssh "DISPLAY=:0 dconf read /org/cinnamon/enabled-applets" 2>/dev/null)

# Check if our applet is already in the list
if echo "$current" | grep -q "$APPLET_UUID"; then
    echo -e "  ${GREEN}Applet already in panel config${NC}"
else
    # Remove stock applets and add ours
    new_config=$(echo "$current" | python3 -c "
import sys, ast
applets = ast.literal_eval(sys.stdin.read().strip())
# Remove stock systray and xapp-status
applets = [a for a in applets if 'systray@cinnamon.org' not in a and 'xapp-status@cinnamon.org' not in a]
# Insert our applet before notifications (or at end of right zone)
insert_idx = next((i for i, a in enumerate(applets) if 'notifications@cinnamon.org' in a), len(applets))
# Use instance ID 15 to avoid conflicts
applets.insert(insert_idx, 'panel1:right:0:$APPLET_UUID:15')
# Reindex right-side positions
right_idx = 0
result = []
for a in applets:
    parts = a.split(':')
    if parts[1] == 'right':
        parts[2] = str(right_idx)
        right_idx += 1
    result.append(':'.join(parts))
print(repr(result))
")
    vm_ssh "DISPLAY=:0 dconf write /org/cinnamon/enabled-applets \"$new_config\"" 2>/dev/null
    echo -e "  ${GREEN}Panel configured: stock applets removed, ours added${NC}"
fi

# --- Step 6: Start tray apps ---
echo ""
echo -e "${BOLD}[6/7] Starting tray applications...${NC}"

for app in "${TRAY_APPS[@]}"; do
    if ! vm_ssh "pgrep -f $app" &>/dev/null; then
        vm_ssh "DISPLAY=:0 nohup $app >/dev/null 2>&1 &" 2>/dev/null
        echo "  Started: $app"
    else
        echo "  Already running: $app"
    fi
done

# Also start blueman if installed
if vm_ssh "command -v blueman-applet" &>/dev/null; then
    if ! vm_ssh "pgrep -f blueman-applet" &>/dev/null; then
        vm_ssh "DISPLAY=:0 nohup blueman-applet >/dev/null 2>&1 &" 2>/dev/null
        echo "  Started: blueman-applet"
    else
        echo "  Already running: blueman-applet"
    fi
fi

# --- Step 7: Restart Cinnamon ---
echo ""
echo -e "${BOLD}[7/7] Restarting Cinnamon...${NC}"

vm_ssh "DISPLAY=:0 nohup cinnamon --replace >/tmp/cinnamon.log 2>&1 &" 2>/dev/null
sleep 5

# Verify applet loaded
if vm_ssh "grep -q 'Loaded applet $APPLET_UUID' /tmp/cinnamon.log" 2>/dev/null; then
    echo -e "  ${GREEN}Applet loaded successfully${NC}"
else
    echo -e "  ${RED}WARNING: Applet load message not found in log${NC}"
    vm_ssh "tail -20 /tmp/cinnamon.log" 2>/dev/null | head -10
fi

# Count managed icons
icon_count=$(vm_ssh "DISPLAY=:0 dbus-send --session --dest=org.Cinnamon \
    --type=method_call --print-reply /org/Cinnamon org.Cinnamon.Eval \
    string:'
let ids = [];
const Main = imports.ui.main;
let panels = Main.panelManager.panels;
for (let p of panels) {
  if (!p) continue;
  for (let z of [p._rightBox, p._leftBox, p._centerBox]) {
    for (let c of z.get_children()) {
      if (c._delegate && c._delegate._managedIcons)
        c._delegate._managedIcons.forEach((v, k) => ids.push(k));
    }
  }
}
ids.length;
'" 2>/dev/null | grep 'string' | grep -oP '\d+' || echo "?")

echo -e "  ${GREEN}Managed icons: $icon_count${NC}"

# --- Snapshot ---
if $DO_SNAPSHOT; then
    echo ""
    echo -e "${BOLD}Taking snapshot...${NC}"
    snapshot_name="test-env-$(date +%Y%m%d-%H%M)"
    "$VM_CTL" snapshot "$snapshot_name"
    echo -e "  ${GREEN}Snapshot: $snapshot_name${NC}"
fi

echo ""
echo -e "${BOLD}═══════════════════════════════════════════════${NC}"
echo -e "${GREEN}  Test environment ready!${NC}"
echo -e "${BOLD}═══════════════════════════════════════════════${NC}"
echo ""
echo "  Run tests:     npm test                     (unit tests)"
echo "  Run VM tests:  ./test/vm-smoke-test.sh       (VM integration)"
echo "  Open viewer:   ./vm/vm-ctl.sh viewer"
echo ""
