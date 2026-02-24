#!/bin/bash
# Create a Cinnamon desktop development VM using libvirt/KVM
# Ubuntu 24.04 server cloud image + cloud-init to install Cinnamon 6
#
# Usage: ./create-vm.sh
#
# After creation, cloud-init installs the desktop environment (~15-20 min).
# Monitor progress: ./vm-ctl.sh cloud-init-log
# View desktop:     ./vm-ctl.sh viewer

set -eo pipefail

VM_NAME="cinnamon-dev"
VM_RAM=8192         # 8 GiB
VM_CPUS=4
VM_DISK_SIZE=40     # GiB
CLOUD_IMG_URL="https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
IMAGES_DIR="/var/lib/libvirt/images"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== Creating VM: $VM_NAME ==="
echo "  RAM: ${VM_RAM}M | CPUs: $VM_CPUS | Disk: ${VM_DISK_SIZE}G"
echo ""

# Pre-flight checks
if ! command -v virsh &>/dev/null; then
    echo "Error: virsh not found. Install: sudo apt install libvirt-clients"
    exit 1
fi

if ! sudo virsh net-info default &>/dev/null 2>&1; then
    echo "Error: libvirt default network not available."
    echo "  Start it: sudo virsh net-start default"
    exit 1
fi

if sudo virsh dominfo "$VM_NAME" &>/dev/null 2>&1; then
    echo "Error: VM '$VM_NAME' already exists."
    echo "  To delete: sudo virsh destroy $VM_NAME 2>/dev/null; sudo virsh undefine $VM_NAME --remove-all-storage"
    exit 1
fi

# Download cloud image (cached in ~/.cache)
CACHE_DIR="$HOME/.cache/cloud-images"
mkdir -p "$CACHE_DIR"
IMG_FILE="$CACHE_DIR/noble-server-cloudimg-amd64.img"

if [[ ! -f "$IMG_FILE" ]]; then
    echo "Downloading Ubuntu 24.04 cloud image..."
    curl -L --progress-bar -o "$IMG_FILE.tmp" "$CLOUD_IMG_URL"
    mv "$IMG_FILE.tmp" "$IMG_FILE"
else
    echo "Using cached cloud image: $IMG_FILE"
fi

# Create VM disk from cloud image
echo "Creating VM disk (${VM_DISK_SIZE}G)..."
sudo cp "$IMG_FILE" "$IMAGES_DIR/${VM_NAME}.qcow2"
sudo qemu-img resize "$IMAGES_DIR/${VM_NAME}.qcow2" "${VM_DISK_SIZE}G"

# Create cloud-init seed ISO
echo "Creating cloud-init seed ISO..."
SEED_ISO="/tmp/${VM_NAME}-seed.iso"
cloud-localds "$SEED_ISO" \
    "$SCRIPT_DIR/cloud-init/user-data" \
    "$SCRIPT_DIR/cloud-init/meta-data"
sudo mv "$SEED_ISO" "$IMAGES_DIR/${VM_NAME}-seed.iso"

# Create the VM
echo "Creating VM with virt-install..."
sudo virt-install \
    --name "$VM_NAME" \
    --ram "$VM_RAM" \
    --vcpus "$VM_CPUS" \
    --os-variant ubuntu24.04 \
    --import \
    --disk "path=$IMAGES_DIR/${VM_NAME}.qcow2,format=qcow2" \
    --disk "path=$IMAGES_DIR/${VM_NAME}-seed.iso,device=cdrom" \
    --graphics spice,listen=none \
    --video virtio \
    --channel spicevmc \
    --network network=default \
    --memorybacking source.type=memfd,access.mode=shared \
    --filesystem "source=/home/steve/dev,target=devmount,driver.type=virtiofs" \
    --noautoconsole

echo ""
echo "=== VM '$VM_NAME' created and booting ==="
echo ""
echo "Cloud-init is now installing Cinnamon desktop (~15-20 min)."
echo ""
echo "Quick reference (or use ./vm-ctl.sh):"
echo "  View desktop:  virt-viewer $VM_NAME"
echo "  SSH:           ssh steve@\$(virsh domifaddr $VM_NAME | grep -oP '\\d+\\.\\d+\\.\\d+')"
echo "  Console:       virsh console $VM_NAME"
echo "  Status:        virsh domstate $VM_NAME"
echo ""
echo "After provisioning completes:"
echo "  Snapshot:      virsh snapshot-create-as $VM_NAME clean-baseline"
echo "  Revert:        virsh snapshot-revert $VM_NAME clean-baseline"
echo ""
echo "Login: steve / dev"
