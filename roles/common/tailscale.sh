#!/usr/bin/env bash
# roles/common/tailscale.sh
set -euo pipefail
log() { echo "[tailscale] $*"; }

if ! command -v tailscale >/dev/null; then
  log "Installing Tailscale"
  curl -fsSL https://tailscale.com/install.sh | sh
fi

log "Configuring Tailscale"
tailscale up --authkey="$TAILSCALE_AUTHKEY" --accept-routes --accept-dns=false --advertise-tags=tag:devbox || true  # idempotent

log "Tailscale ready"
