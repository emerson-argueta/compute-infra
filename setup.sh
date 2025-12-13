#!/usr/bin/env bash
# setup.sh — tiny driver
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG="/var/log/compute-infra-setup.log"
ROLE="${1:-}"

log() { echo -e "[$(date +'%H:%M:%S')] $*" | tee -a "$LOG"; }

case "$ROLE" in
  node1|node2|devbox) ;;
  -h|--help|"") echo "Usage: sudo $0 [node1|node2|devbox]" && exit 0 ;;
  *) echo "Invalid role: $ROLE" && exit 1 ;;
esac

[[ $EUID == 0 ]] || { echo "Run as root"; exit 1; }

log "=== Starting $ROLE setup ==="

export ROLE
set -a
[[ -f "$SCRIPT_DIR/.env.inventory" ]] && source "$SCRIPT_DIR/.env.inventory"
set +a

"$SCRIPT_DIR/roles/common/prereqs.sh"
"$SCRIPT_DIR/roles/common/docker.sh"
"$SCRIPT_DIR/roles/common/firewall.sh"
"$SCRIPT_DIR/roles/$ROLE/configure.sh"

log "=== $ROLE setup complete ==="
