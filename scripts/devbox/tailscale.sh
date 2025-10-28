#!/bin/bash
# scripts/devbox/tailscale.sh
# Install and configure Tailscale on devbox

set -euo pipefail

log() { echo "[+] $*"; }

log "Installing Tailscale..."

# Install
curl -fsSL https://tailscale.com/install.sh | sh

# Start and authenticate
log "Starting Tailscale... open this URL in your browser:"
sudo tailscale up

log "Tailscale installed. Use 'tailscale status' to verify."
