#!/usr/bin/env bash
# scripts/common/firewall.sh — safe & minimal
set -euo pipefail

log() { echo "[+] $*"; }

# Detect Tailscale interface (works even if not up yet)
TS_IFACE="$(ip -j link | jq -r '.[] | select(.operstate=="UP" and .link_type=="ether" and .address|test(".:.:.:.:.:.")) | .ifname' | head -n1 || echo "tailscale0")"

log "Using Tailscale interface: $TS_IFACE"

# Reset only reset if we are the ones who created the rules (idempotent + safe)
if ufw status | grep -q "compute-infra"; then
    log "Existing compute-infra rules found → deleting only ours"
    ufw --force delete $(ufw status numbered | grep compute-infra | awk -F'[][]' '{print $2}' | tac)
else
    log "No previous compute-infra rules → full reset (first run)"
    ufw --force reset
fi

ufw default deny incoming
ufw default allow outgoing

# Tailscale – always allowed in both directions
ufw allow in  on "$TS_IFACE"  comment "Tailscale inbound – compute-infra"
ufw allow out on "$TS_IFACE"  comment "Tailscale outbound – compute-infra"

# Docker Swarm – ONLY on Tailscale interface
ufw allow in on "$TS_IFACE" to any port 2376,2377 proto tcp comment "Swarm mgmt – compute-infra"
ufw allow in on "$TS_IFACE" to any port 7946     proto tcp comment "Swarm overlay – compute-infra"
ufw allow in on "$TS_IFACE" to any port 7946     proto udp comment "Swarm overlay – compute-infra"
ufw allow in on "$TS_IFACE" to any port 4789     proto udp comment "Swarm VXLAN – compute-infra"

# devbox only – public HTTP/S
if [[ "$(hostname)" == devbox* ]] || -n "${DEVBOX_IP:-}" ]]; then
    ufw allow 80/tcp   comment "HTTP → HTTPS redirect – compute-infra"
    ufw allow 443/tcp  comment "HTTPS Traefik – compute-infra"
fi

# Omarchy VM ports – ONLY from Tailscale
ufw allow in on "$TS_IFACE" to any port 2200:2299 proto tcp comment "Omarchy SSH ports – compute-infra"
ufw allow in on "$TS_IFACE" to any port 5900:5999 proto tcp comment "Omarchy VNC ports – compute-infra"

# arch-dev API – only Tailscale
ufw allow in on "$TS_IFACE" to any port 5000 proto tcp comment "arch-dev API – compute-infra"

# Emergency SSH – restrict to your personal IP or Tailscale only if possible
# Change 203.0.113.0/24 to your home/office public subnet or remove entirely
# ufw allow from 203.0.113.0/24 to any port 22 proto tcp comment "Emergency SSH – compute-infra"

# OPTIONAL: completely disable public SSH (recommended)
# comment the line above and leave only this:
ufw delete allow 22 2>/dev/null || true

ufw --force enable
log "Firewall configured. Only Tailscale + (on devbox) 80/443 are reachable."
ufw status verbose