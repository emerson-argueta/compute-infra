#!/bin/bash
# scripts/devbox/devbox-setup.sh
# Full setup for devbox (Tailscale, Traefik, Gitea, Nextcloud, VNC)

set -euo pipefail

log() { echo "[+] $*"; }

log "Starting devbox setup..."

# === 1. Tailscale ===
./tailscale.sh

# === 2. Create network ===
log "Creating devnet network..."
docker network create devnet || true

# === 3. Create dynamic config dir ===
mkdir -p dynamic

# === 4. Deploy Traefik ===
log "Deploying Traefik..."
docker-compose -f traefik.yml up -d

# === 5. Deploy Gitea ===
log "Deploying Gitea..."
docker-compose -f gitea.yml up -d

# === 6. Deploy Nextcloud ===
log "Deploying Nextcloud..."
docker-compose -f nextcloud.yml up -d

# === 7. Deploy Arch VNC Template ===
log "Deploying Omarchy VNC template..."
docker-compose -f arch-vnc.yml up -d

log "devbox setup complete!"
log ""
log "Access:"
log "  - Gitea:     https://git.yourdomain.com"
log "  - Files:     https://files.yourdomain.com"
log "  - VNC:       https://arch.yourdomain.com"
log ""
log "Use 'arch-dev' CLI to launch dynamic instances."
