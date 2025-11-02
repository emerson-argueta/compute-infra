#!/bin/bash
# omarchy/create-base-qcow2.sh
# Create the golden base.qcow2 image for Omarchy cloud instances
# Run ONCE on node3 (or any machine with KVM)

set -euo pipefail

log() { echo "[+] $*"; }
error() { echo "[ERROR] $*"; exit 1; }

# === CONFIG ===
ISO_PATH="${1:-omarchy-custom.iso}"      # Path to your Omarchy ISO
BASE_IMAGE="omarchy/base.qcow2"
BASE_SIZE="20G"                          # Disk size
RAM="2048"                               # Install RAM
VCPUS="2"
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
TARGET_PATH="$REPO_ROOT/$BASE_IMAGE"

# === VALIDATE ===
[[ -f "$ISO_PATH" ]] || error "ISO not found: $ISO_PATH"
[[ -d "$REPO_ROOT/.git" ]] || error "Not in a Git repo. Run from 3node-infra/"

log "Creating Omarchy base image: $TARGET_PATH"

# === 1. Create empty QCOW2 disk ===
log "Creating $BASE_SIZE QCOW2 disk..."
qemu-img create -f qcow2 "$TARGET_PATH.tmp" "$BASE_SIZE"

# === 2. Boot installer with install.sh ===
log "Booting installer from $ISO_PATH..."
virt-install \
  --name omarchy-base-install \
  --ram "$RAM" \
  --vcpus "$VCPUS" \
  --disk path="$TARGET_PATH.tmp",format=qcow2 \
  --cdrom "$ISO_PATH" \
  --os-variant archlinux \
  --network network=default \
  --graphics none \
  --console pty,target.type=serial \
  --import \
  --wait -1

# === 3. Wait for shutdown ===
log "Waiting for installation to complete and shutdown..."
while virsh domstate omarchy-base-install 2>/dev/null | grep -q running; do
    sleep 5
done

# === 4. Clean up VM definition ===
virsh undefine omarchy-base-install || true

# === 5. Finalize image ===
log "Finalizing image..."
mv "$TARGET_PATH.tmp" "$TARGET_PATH"
qemu-img convert -O qcow2 -c "$TARGET_PATH" "$TARGET_PATH.compressed"
mv "$TARGET_PATH.compressed" "$TARGET_PATH"

log ""
log "base.qcow2 created successfully!"
log "   Path: $TARGET_PATH"
log "   Size: $(du -h "$TARGET_PATH" | cut -f1)"
log ""
log "Next: Commit this script + README, then use 'arch-dev' to clone instances."
