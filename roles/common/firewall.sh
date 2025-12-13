#!/usr/bin/env bash
# roles/common/firewall.sh
set -euo pipefail
log() { echo "[firewall] $*"; }

TS_IFACE=$(ip -j link show up | jq -r '.[].ifname' | grep -m1 tailscale || echo "tailscale0")
log "Using Tailscale interface: $TS_IFACE"

ufw --force reset >/dev/null 2>&1
ufw default deny incoming
ufw default allow outgoing

ufw allow in  on "$TS_IFACE"  comment "Tailscale"
ufw allow out on "$TS_IFACE"  comment "Tailscale"

ufw allow in on "$TS_IFACE" to any port 2376,2377 proto tcp   comment "Swarm mgmt"
ufw allow in on "$TS_IFACE" to any port 7946 proto tcp,udp    comment "Swarm overlay"
ufw allow in on "$TS_IFACE" to any port 4789 proto udp        comment "Swarm VXLAN"

if [[ "${ROLE:-}" == "devbox" ]]; then
  ufw allow 80/tcp   comment "HTTP → HTTPS"
  ufw allow 443/tcp  comment "HTTPS Traefik"
fi

ufw allow in on "$TS_IFACE" to any port 2200:2299 proto tcp comment "VM SSH"
ufw allow in on "$TS_IFACE" to any port 5900:5999 proto tcp comment "VM VNC"
ufw allow in on "$TS_IFACE" to any port 5000 proto tcp comment "arch-dev API"

ufw --force enable
log "Firewall locked down – only Tailscale + (devbox) 80/443 open"
