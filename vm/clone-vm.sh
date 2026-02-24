#!/bin/bash
# Clone the cinnamon-dev baseline into a new independent VM
#
# Uses qcow2 backing chains for space efficiency: the new VM shares
# the baseline image (read-only) and only stores its own changes.
#
# Usage: ./clone-vm.sh <new-vm-name> [--ram 8192] [--cpus 4] [--mount /path:target:ro]
#
# Examples:
#   ./clone-vm.sh applet-test                           # Clone for testing
#   ./clone-vm.sh claude-sandbox --ram 4096 --cpus 2    # Lightweight clone
#   ./clone-vm.sh dev-box --mount /home/steve/dev:devmount:ro  # Custom mount

set -eo pipefail

TEMPLATE_VM="cinnamon-dev"
SNAPSHOT="clean-baseline"
IMAGES_DIR="/var/lib/libvirt/images"
TEMPLATE_IMG="$IMAGES_DIR/${TEMPLATE_VM}-template.qcow2"

# Defaults
NEW_RAM=8192
NEW_CPUS=4
MOUNTS=()

# Parse arguments
NEW_NAME="${1:-}"
if [[ -z "$NEW_NAME" ]]; then
    echo "Usage: $0 <new-vm-name> [--ram N] [--cpus N] [--mount /path:target:ro|rw]"
    echo ""
    echo "Creates a new VM from the cinnamon-dev clean-baseline snapshot."
    echo "The new VM shares the base image (copy-on-write) for efficiency."
    exit 1
fi
shift

while [[ $# -gt 0 ]]; do
    case "$1" in
        --ram)   NEW_RAM="$2"; shift 2 ;;
        --cpus)  NEW_CPUS="$2"; shift 2 ;;
        --mount) MOUNTS+=("$2"); shift 2 ;;
        *)       echo "Unknown option: $1"; exit 1 ;;
    esac
done

# Use virsh directly or via sudo
VIRSH="virsh"
if ! virsh list &>/dev/null 2>&1; then
    VIRSH="sudo virsh"
fi

# Check the new name doesn't already exist
if $VIRSH dominfo "$NEW_NAME" &>/dev/null 2>&1; then
    echo "Error: VM '$NEW_NAME' already exists."
    exit 1
fi

# Create template image from snapshot (one-time, reused by all clones)
if [[ ! -f "$TEMPLATE_IMG" ]]; then
    echo "Creating template image from '$TEMPLATE_VM' snapshot '$SNAPSHOT'..."

    # Revert to clean baseline to ensure disk is in the right state
    $VIRSH snapshot-revert "$TEMPLATE_VM" "$SNAPSHOT" 2>/dev/null || true

    # Copy the current disk state as the template (backing image)
    sudo cp "$IMAGES_DIR/${TEMPLATE_VM}.qcow2" "$TEMPLATE_IMG"
    sudo chmod 644 "$TEMPLATE_IMG"
    echo "Template image created: $TEMPLATE_IMG"
fi

# Create new disk using template as backing file (copy-on-write)
NEW_IMG="$IMAGES_DIR/${NEW_NAME}.qcow2"
echo "Creating CoW disk for '$NEW_NAME'..."
sudo qemu-img create -f qcow2 -b "$TEMPLATE_IMG" -F qcow2 "$NEW_IMG"
sudo qemu-img resize "$NEW_IMG" 40G

# Build virt-install command
VIRT_CMD=(
    sudo virt-install
    --name "$NEW_NAME"
    --ram "$NEW_RAM"
    --vcpus "$NEW_CPUS"
    --os-variant ubuntu24.04
    --import
    --disk "path=$NEW_IMG,format=qcow2"
    --graphics spice,listen=none
    --video qxl
    --channel spicevmc
    --network network=default
    --noautoconsole
)

# Add filesystem mounts if any (requires shared memory)
if [[ ${#MOUNTS[@]} -gt 0 ]]; then
    VIRT_CMD+=(--memorybacking source.type=memfd,access.mode=shared)
    for mount_spec in "${MOUNTS[@]}"; do
        IFS=: read -r src target mode <<< "$mount_spec"
        fs_arg="source=$src,target=$target,driver.type=virtiofs"
        if [[ "$mode" == "ro" ]]; then
            fs_arg="$fs_arg,readonly=on"
        fi
        VIRT_CMD+=(--filesystem "$fs_arg")
    done
fi

echo "Creating VM '$NEW_NAME'..."
"${VIRT_CMD[@]}"

# Set hostname inside the clone via cloud-init re-run
echo "Waiting for VM to boot..."
sleep 15

NEW_IP=""
for i in $(seq 1 30); do
    NEW_IP=$($VIRSH domifaddr "$NEW_NAME" 2>/dev/null | grep -oP '\d+\.\d+\.\d+\.\d+' | head -1)
    if [[ -n "$NEW_IP" ]]; then break; fi
    sleep 2
done

if [[ -n "$NEW_IP" ]]; then
    echo "Setting hostname to '$NEW_NAME'..."
    ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
        steve@"$NEW_IP" "sudo hostnamectl set-hostname $NEW_NAME" 2>/dev/null || true
fi

echo ""
echo "=== VM '$NEW_NAME' created ==="
echo "  IP: ${NEW_IP:-pending}"
echo "  RAM: ${NEW_RAM}M | CPUs: $NEW_CPUS"
echo "  Disk: $NEW_IMG (CoW, backed by template)"
echo ""
echo "  SSH:    ssh steve@$NEW_IP"
echo "  Viewer: virt-viewer $NEW_NAME"
echo "  Stop:   virsh shutdown $NEW_NAME"
echo "  Delete: virsh destroy $NEW_NAME; virsh undefine $NEW_NAME --remove-all-storage"
echo ""
echo "Login: steve / dev"
