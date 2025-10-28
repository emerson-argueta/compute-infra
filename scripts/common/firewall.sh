#!/bin/bash
# scripts/common/firewall.sh
# Secure UFW firewall configuration for 3-node infra
# Run on all machines: node1, node2, devbox

set -euo pipefail

log() { echo "[+] $*"; }
warn() { echo "[!] $*"; }
error() { echo "[ERROR] $*"; exit 1; }

log "Configuring UFW firewall..."

# === 1. Enable UFW (deny by default) ===
if ! sudo ufw status | grep -q "Status: active"; then
    log "Enabling UFW with deny-by-default..."
    sudo ufw --force reset
    sudo ufw default deny incoming
    sudo ufw default allow outgoing
    sudo ufw --force enable
else
    log "UFW already active. Resetting rules..."
    sudo ufw --force reset
    sudo ufw default deny incoming
    sudo ufw default allow outgoing
fi

# === 2. Allow SSH (emergency access) ===
log "Allowing SSH (22)..."
sudo ufw allow 22/tcp comment "SSH"

# === 3. Allow Tailscale (private network) ===
log "Allowing Tailscale (UDP 41641)..."
sudo ufw allow in on tailscale0 comment "Tailscale"
sudo ufw allow out on tailscale0 comment "Tailscale"

# === 4. Machine-specific rules ===
MACHINE_ROLE=""
case $(hostname) in
    node1*)
        MACHINE_ROLE="node1"
        ;;
    node2*)
        MACHINE_ROLE="node2"
        ;;
    devbox*)
        MACHINE_ROLE="devbox"
        ;;
    *)
        warn "Unknown hostname. Using default rules."
        ;;
esac

log "Applying rules for $MACHINE_ROLE..."

case $MACHINE_ROLE in
    node1)
        # PoC Manager: Swarm, MQTT, Postgres, Harbor, API
        sudo ufw allow 2376/tcp comment "Docker Swarm (TLS)"
        sudo ufw allow 2377/tcp comment "Swarm cluster mgmt"
        sudo ufw allow 7946/tcp comment "Swarm overlay"
        sudo ufw allow 7946/udp comment "Swarm overlay"
        sudo ufw allow 4789/udp comment "Swarm VXLAN"
        sudo ufw allow 1883/tcp comment "MQTT"
        sudo ufw allow 5432/tcp comment "PostgreSQL"
        sudo ufw allow 5000/tcp comment "Harbor Registry"
        sudo ufw allow 5000/tcp comment "arch-dev API"
        ;;
    node2)
        # GPU Worker: Only Swarm + GPU
        sudo ufw allow 2376/tcp comment "Docker Swarm"
        sudo ufw allow 2377/tcp comment "Swarm cluster"
        sudo ufw allow 7946/tcp comment "Swarm overlay"
        sudo ufw allow 7946/udp comment "Swarm overlay"
        sudo ufw allow 4789/udp comment "Swarm VXLAN"
        # No public services
        ;;
    devbox)
        # Dev Workstation: Public services
        sudo ufw allow 80/tcp comment "HTTP (Traefik)"
        sudo ufw allow 443/tcp comment "HTTPS (Traefik)"
        sudo ufw allow 6080:6099/tcp comment "noVNC (ephemeral)"
        sudo ufw allow 2200:2299/tcp comment "SSH (ephemeral)"
        ;;
esac

# === 5. Reload UFW ===
log "Reloading UFW..."
sudo ufw reload

# === 6. Show final rules ===
log "Firewall rules applied:"
sudo ufw status verbose

log "UFW firewall configured and active."
