#!/usr/bin/env bash
# roles/devbox/configure.sh — devbox-specific setup
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log() { echo "[devbox] $*"; }

if ! REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null)"; then
  log "WARNING: Not a git repo — using path fallback"
  REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
fi

log "Starting devbox configuration"

log "Configuring Tailscale"
"$SCRIPT_DIR/../common/tailscale.sh" || { log "FATAL: Tailscale failed"; exit 1; }

shopt -s nullglob
yml_files=("$SCRIPT_DIR"/*.yml)
if [[ ${#yml_files[@]} -eq 0 ]]; then
  log "No compose files found in $SCRIPT_DIR"
else
  log "Deploying ${#yml_files[@]} service(s)"
  for yml in "${yml_files[@]}"; do
    svc="$(basename "$yml" .yml)"
    if [[ "$svc" =~ \.(bak|old|swp|tmp)$ || "$svc" =~ ~$ ]]; then
      log "Skipping backup file: $yml"
      continue
    fi
    log "Deploying $svc"
    docker compose -f "$yml" up -d --wait --remove-orphans || { log "FATAL: Failed to deploy $svc"; exit 1; }
  done
fi

log "Installing arch-dev CLI"
mkdir -p /opt/compute-infra/cli
CLI_SOURCE="$REPO_ROOT/cli/arch-dev"
if [[ ! -f "$CLI_SOURCE" ]]; then
  log "FATAL: arch-dev CLI missing at $CLI_SOURCE"
  exit 1
fi
cp "$CLI_SOURCE" /opt/compute-infra/cli/arch-dev
chmod +x /opt/compute-infra/cli/arch-dev
log "arch-dev CLI installed"

log "devbox configuration complete"
