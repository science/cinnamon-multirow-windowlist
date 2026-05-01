#!/bin/bash
# Fix networking on a cloned VM by resetting cloud-init and netplan
# Usage: sudo ./fix-clone-network.sh <vm-name>
#
# The problem: cloned VMs get a new MAC address, but cloud-init already ran
# in the base image, so netplan may reference the old interface configuration.
# This script mounts the disk, resets cloud-init, and ensures netplan uses DHCP.

set -eo pipefail

VM_NAME="${1:?Usage: $0 <vm-name>}"
IMAGES_DIR="/var/lib/libvirt/images"
DISK_IMG="$IMAGES_DIR/${VM_NAME}.qcow2"
MOUNT_POINT="/tmp/fix-clone-$$"
NBD_DEV="/dev/nbd0"

if [[ ! -f "$DISK_IMG" ]]; then
    echo "Error: Disk image not found: $DISK_IMG"
    exit 1
fi

# Shut down VM if running
state=$(virsh domstate "$VM_NAME" 2>/dev/null || echo "unknown")
if [[ "$state" == "running" ]]; then
    echo "Stopping VM..."
    virsh destroy "$VM_NAME"
    sleep 2
fi

# Load NBD module and connect disk
echo "Mounting disk..."
modprobe nbd max_part=8
qemu-nbd --connect="$NBD_DEV" "$DISK_IMG"
sleep 2

# Find the root partition (usually nbd0p1 for cloud images)
PART="${NBD_DEV}p1"
if [[ ! -b "$PART" ]]; then
    echo "Error: Partition $PART not found. Trying nbd0p2..."
    PART="${NBD_DEV}p2"
fi

mkdir -p "$MOUNT_POINT"
mount "$PART" "$MOUNT_POINT"

echo "Fixing network configuration..."

# Write a generic netplan config that works with any MAC
mkdir -p "$MOUNT_POINT/etc/netplan"
cat > "$MOUNT_POINT/etc/netplan/01-dhcp-all.yaml" << 'NETPLAN'
network:
  version: 2
  ethernets:
    id0:
      match:
        name: "en*"
      dhcp4: true
NETPLAN

# Remove any cloud-init netplan configs that might conflict
rm -f "$MOUNT_POINT/etc/netplan/50-cloud-init.yaml"

# Reset cloud-init so it re-runs network setup
rm -rf "$MOUNT_POINT/var/lib/cloud/instances"
rm -f "$MOUNT_POINT/var/lib/cloud/instance"

echo "Unmounting..."
umount "$MOUNT_POINT"
qemu-nbd --disconnect "$NBD_DEV"
rmdir "$MOUNT_POINT"

echo "Starting VM..."
virsh start "$VM_NAME"

echo ""
echo "VM '$VM_NAME' restarted with fixed networking."
echo "Wait ~30s for boot, then check: virsh domifaddr $VM_NAME"
