#!/usr/bin/env bash
# omarchy/create-base-qcow2.sh — create golden base image from official Arch cloud image
# Run ONCE on any machine with KVM
set -euo pipefail

log() { echo "[+] $*"; }
error() { echo "[ERROR] $*"; exit 1; }

BASE_SIZE="20G"
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
TARGET_DIR="$REPO_ROOT/omarchy"
TARGET_PATH="$TARGET_DIR/base.qcow2"

mkdir -p "$TARGET_DIR"

TMP_IMAGE="$TARGET_DIR/base.tmp.qcow2"

log "Downloading latest official Arch Linux cloud image (always fresh & secure)..."
curl -L -o "$TMP_IMAGE" "https://geo.mirror.pkgbuild.com/images/latest/Arch-Linux-x86_64-cloudimg.qcow2"

log "Resizing to $BASE_SIZE..."
qemu-img resize "$TMP_IMAGE" "$BASE_SIZE"

log "Compressing with zstd (modern, fast, better ratio)..."
qemu-img convert -O qcow2 -c -o compression_type=zstd "$TMP_IMAGE" "$TARGET_PATH"

rm "$TMP_IMAGE"

log ""
log "base.qcow2 created successfully!"
log " Path: $TARGET_PATH"
log " Size: $(du -h "$TARGET_PATH" | cut -f1)"
log ""
log "This is the official Arch cloud image — minimal, up-to-date, cloud-init ready."
log "Customize further by starting a VM, applying Minarchy configs, then promoting its disk to base."
log "Commit the new base.qcow2 and push."

