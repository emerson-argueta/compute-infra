#!/usr/bin/env bash
# roles/common/firewall.sh — safe, idempotent, practical (for real)
set -euo pipefail

log() { echo "[firewall] $*"; }

TS_IFACE="tailscale0"
TAG="compute-infra"

log "Applying firewall rules (idempotent)"

ufw default deny incoming
ufw default allow outgoing
ufw allow in on "$TS_IFACE" comment "$TAG: Tailscale" || true
ufw allow in on "$TS_IFACE" 2377/tcp comment "$TAG: Swarm manager" || true
ufw allow in on "$TS_IFACE" 7946/tcp,udp comment "$TAG: Swarm discovery" || true
ufw allow in on "$TS_IFACE" 4789/udp comment "$TAG: Swarm overlay" || true

if [[ "${ROLE:-}" == "devbox" ]]; then
  ufw allow 80/tcp comment "$TAG: HTTP → HTTPS" || true
  ufw allow 443/tcp comment "$TAG: HTTPS Traefik" || true
fi
if ! ufw status | grep -q "Status: active"; then
  log "Enabling UFW"
  ufw --force enable
fi

log "Firewall rules applied (duplicates ignored)"
ufw status verbose
