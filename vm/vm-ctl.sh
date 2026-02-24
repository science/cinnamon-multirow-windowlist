#!/bin/bash
# VM lifecycle management for cinnamon-dev
#
# Usage: ./vm-ctl.sh <command> [args]
#
# Commands:
#   start              Start the VM
#   stop               Graceful shutdown
#   kill               Force stop
#   status             Show VM state
#   viewer             Open SPICE desktop viewer
#   ssh [cmd]          SSH into VM (or run a command)
#   ip                 Show VM IP address
#   snapshot <name>    Create a snapshot
#   revert <name>      Revert to a snapshot
#   snapshots          List all snapshots
#   cloud-init-log     Tail cloud-init log (provisioning progress)
#   cloud-init-status  Check if cloud-init is done
#   destroy            Delete VM and all storage (asks for confirmation)

set -eo pipefail

VM_NAME="cinnamon-dev"
SSH_USER="steve"
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=5"

# Use sudo for virsh if the VM isn't visible on the default connection
# (virsh without sudo connects to qemu:///session which may not see system VMs)
VIRSH="virsh"
if ! virsh list --all 2>/dev/null | grep -q "$VM_NAME"; then
    VIRSH="sudo virsh"
fi

get_ip() {
    $VIRSH domifaddr "$VM_NAME" 2>/dev/null | grep -oP '\d+\.\d+\.\d+\.\d+' | head -1
}

wait_for_ip() {
    local tries=0
    local ip
    while [[ $tries -lt 30 ]]; do
        ip=$(get_ip)
        if [[ -n "$ip" ]]; then
            echo "$ip"
            return 0
        fi
        sleep 2
        tries=$((tries + 1))
    done
    echo "Error: Could not get VM IP after 60s. Is the VM running?" >&2
    return 1
}

case "${1:-help}" in
    start)
        $VIRSH start "$VM_NAME"
        ;;

    stop)
        # SSH shutdown is more reliable than ACPI in cloud-init VMs
        ip=$(get_ip)
        if [[ -n "$ip" ]]; then
            ssh $SSH_OPTS "$SSH_USER@$ip" "sudo shutdown -h now" 2>/dev/null || true
            for i in $(seq 1 15); do
                [[ "$($VIRSH domstate "$VM_NAME" 2>/dev/null)" == "shut off" ]] && break
                sleep 2
            done
        fi
        # Force off if still running
        if [[ "$($VIRSH domstate "$VM_NAME" 2>/dev/null)" != "shut off" ]]; then
            $VIRSH destroy "$VM_NAME"
        fi
        echo "VM stopped."
        ;;

    kill)
        $VIRSH destroy "$VM_NAME"
        ;;

    status)
        $VIRSH domstate "$VM_NAME"
        ;;

    viewer)
        virt-viewer "$VM_NAME" &
        disown
        echo "SPICE viewer launched."
        ;;

    ssh)
        ip=$(wait_for_ip)
        shift
        if [[ $# -gt 0 ]]; then
            ssh $SSH_OPTS "$SSH_USER@$ip" "$@"
        else
            ssh $SSH_OPTS "$SSH_USER@$ip"
        fi
        ;;

    ip)
        ip=$(get_ip)
        if [[ -n "$ip" ]]; then
            echo "$ip"
        else
            echo "VM has no IP. Is it running?"
            exit 1
        fi
        ;;

    snapshot)
        if [[ -z "${2:-}" ]]; then
            echo "Usage: $0 snapshot <name>"
            exit 1
        fi
        # virtiofs prevents live snapshots; shut down first if running
        state=$($VIRSH domstate "$VM_NAME" 2>/dev/null)
        if [[ "$state" == "running" ]]; then
            echo "Shutting down VM for snapshot (virtiofs requires offline snapshots)..."
            $VIRSH shutdown "$VM_NAME"
            for i in $(seq 1 30); do
                [[ "$($VIRSH domstate "$VM_NAME" 2>/dev/null)" == "shut off" ]] && break
                sleep 2
            done
        fi
        $VIRSH snapshot-create-as "$VM_NAME" "$2"
        echo "Snapshot '$2' created."
        if [[ "$state" == "running" ]]; then
            echo "Restarting VM..."
            $VIRSH start "$VM_NAME"
        fi
        ;;

    revert)
        if [[ -z "${2:-}" ]]; then
            echo "Usage: $0 revert <name>"
            exit 1
        fi
        $VIRSH snapshot-revert "$VM_NAME" "$2"
        echo "Reverted to snapshot '$2'."
        ;;

    snapshots)
        $VIRSH snapshot-list "$VM_NAME"
        ;;

    cloud-init-log)
        ip=$(wait_for_ip)
        ssh $SSH_OPTS "$SSH_USER@$ip" "sudo tail -f /var/log/cloud-init-output.log"
        ;;

    cloud-init-status)
        ip=$(wait_for_ip)
        ssh $SSH_OPTS "$SSH_USER@$ip" "cloud-init status"
        ;;

    clone)
        SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
        shift
        exec "$SCRIPT_DIR/clone-vm.sh" "$@"
        ;;

    destroy)
        read -rp "Delete VM '$VM_NAME' and ALL storage? [y/N] " confirm
        if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
            $VIRSH destroy "$VM_NAME" 2>/dev/null || true
            $VIRSH undefine "$VM_NAME" --remove-all-storage
            echo "VM '$VM_NAME' destroyed."
        else
            echo "Aborted."
        fi
        ;;

    help|*)
        echo "Usage: $0 <command> [args]"
        echo ""
        echo "Commands:"
        echo "  start              Start the VM"
        echo "  stop               Graceful shutdown"
        echo "  kill               Force stop"
        echo "  status             Show VM state"
        echo "  viewer             Open SPICE desktop viewer"
        echo "  ssh [cmd]          SSH into VM (or run a command)"
        echo "  ip                 Show VM IP address"
        echo "  snapshot <name>    Create a snapshot"
        echo "  revert <name>      Revert to a snapshot"
        echo "  snapshots          List all snapshots"
        echo "  clone <name>       Clone baseline into a new VM"
        echo "  cloud-init-log     Tail cloud-init log"
        echo "  cloud-init-status  Check if cloud-init is done"
        echo "  destroy            Delete VM and all storage"
        ;;
esac
