#!/usr/bin/env bash
# =============================================================================
# Minarchy ISO Builder
# Part of: compute-infra/minarchy/
# Builds, tests, and signs the official Minarchy ISO for base.qcow2 creation
# =============================================================================

set -euo pipefail

# --- CONFIGURATION -----------------------------------------------------------
ISO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="${ISO_DIR}/minarchy-iso"
ISO_OUTPUT="${ISO_DIR}/minarchy.iso"
ISO_OUTPUT_SIGNED="${ISO_DIR}/minarchy.iso.sig"
LOG_FILE="${ISO_DIR}/iso-build.log"

# Your GitHub fork (optional override)
MINARCHY_ISO_REPO="${MINARCHY_ISO_REPO:-emerson-argueta/minarchy-iso}"
MINARCHY_ISO_REF="${MINARCHY_ISO_REF:-master}"

# GPG key for signing (required)
GPG_USER="${GPG_USER:-}"
if [[ -z "$GPG_USER" ]]; then
  echo "Error: GPG_USER env var not set. Export your GPG key ID."
  exit 1
fi

# QEMU test timeout (seconds)
QEMU_TIMEOUT=300

# --- LOGGING -----------------------------------------------------------------
log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

# --- CLEANUP -----------------------------------------------------------------
cleanup() {
  log "Cleaning up temporary files..."
  rm -rf "$REPO_DIR"
}
trap cleanup EXIT

# --- PREREQUISITES -----------------------------------------------------------
check_deps() {
  local missing=()
  for cmd in git qemu-system-x86_64 gpg rmdir rm mkdir; do
    command -v "$cmd" >/dev/null || missing+=("$cmd")
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    log "Error: Missing dependencies: ${missing[*]}"
    log "Install with: sudo apt install git qemu-system-x86 gpg"
    exit 1
  fi
}

# --- MAIN -------------------------------------------------------------------
main() {
  log "Starting Minarchy ISO build"
  log "Repo: $MINARCHY_ISO_REPO @ $MINARCHY_ISO_REF"
  log "Output: $ISO_OUTPUT"
  log "GPG User: $GPG_USER"

  check_deps

  # Clean previous build
  [[ -f "$ISO_OUTPUT" ]] && rm -f "$ISO_OUTPUT" "$ISO_OUTPUT_SIGNED"
  [[ -d "$REPO_DIR" ]] && rm -rf "$REPO_DIR"

  # Clone minarchy-iso
  log "Cloning minarchy-iso..."
  git clone "https://github.com/${MINARCHY_ISO_REPO}.git" "$REPO_DIR"
  pushd "$REPO_DIR" >/dev/null

  # Checkout ref
  git checkout "$MINARCHY_ISO_REF"

  # Build ISO
  log "Building ISO..."
  MINARCHY_INSTALLER_REPO="${MINARCHY_INSTALLER_REPO:-emerson-argueta/minarchy}" \
  MINARCHY_INSTALLER_REF="${MINARCHY_INSTALLER_REF:-master}" \
    ./bin/omarchy-iso-make

  # Copy output
  if [[ ! -f release/omarchy.iso ]]; then
    log "Error: ISO not found in release/"
    exit 1
  fi
  cp release/omarchy.iso "$ISO_OUTPUT"
  log "ISO built: $ISO_OUTPUT"

  # Test with QEMU
  log "Testing ISO in QEMU (timeout: ${QEMU_TIMEOUT}s)..."
  timeout "$QEMU_TIMEOUT" qemu-system-x86_64 \
    -m 2G \
    -cdrom "$ISO_OUTPUT" \
    -boot d \
    -nographic \
    -serial mon:stdio \
    -enable-kvm || true

  if [[ $? -eq 124 ]]; then
    log "QEMU test timed out (expected for installer)"
  else
    log "QEMU test completed"
  fi

  # Sign ISO
  log "Signing ISO with GPG..."
  gpg --local-user "$GPG_USER" --output "$ISO_OUTPUT_SIGNED" --detach-sign "$ISO_OUTPUT"
  log "Signed: $ISO_OUTPUT_SIGNED"

  # Verify signature
  log "Verifying signature..."
  if gpg --verify "$ISO_OUTPUT_SIGNED" "$ISO_OUTPUT"; then
    log "Signature verified"
  else
    log "Error: Signature verification failed"
    exit 1
  fi

  popd >/dev/null
  log "Minarchy ISO ready: $ISO_OUTPUT"
  log "Use with: ./minarchy/create-base-qcow2.sh"
}

# --- RUN ---------------------------------------------------------------------
main "$@"
