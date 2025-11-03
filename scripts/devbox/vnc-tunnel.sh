#!/usr/bin/env bash
# scripts/devbox/vnc-tunnel.sh
# Auto-configures SSH tunnel for VNC (client-side helper)

set -euo pipefail

DEVBOX_IP="${DEVBOX_IP:-}"
SSH_PORT="2222"
VNC_LOCAL_PORT="5901"

[[ -n "$DEVBOX_IP" ]] || { echo "DEVBOX_IP not set"; exit 1; }

echo "[+] Starting VNC over SSH tunnel..."
echo "    Connect with: vncviewer localhost:$VNC_LOCAL_PORT"
echo "    Or: vncviewer -via $DEVBOX_IP:$SSH_PORT localhost:5901"

# Kill any existing tunnel
pkill -f "ssh.*5901:localhost:5901" || true

# Start tunnel
ssh -f -N -L "$VNC_LOCAL_PORT:localhost:5901" "omarchy@$DEVBOX_IP" -p "$SSH_PORT"

echo "[+] Tunnel active. Use VNC client to connect to localhost:$VNC_LOCAL_PORT"