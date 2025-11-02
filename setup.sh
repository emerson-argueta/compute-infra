#!/usr/bin/env bash
# =============================================================================
# compute-infra – Master Installer (Self-Contained)
# Run: sudo ./setup.sh --machine [node1|node2|devbox]
# Logs: /var/log/compute-infra-setup.log
# =============================================================================

set -euo pipefail
IFS=$'\n\t'

# ------------------------------- CONFIG ---------------------------------------
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="/var/log/compute-infra-setup.log"
readonly INVENTORY="${SCRIPT_DIR}/inventory.yml"
readonly SWARM_TOKEN_FILE="/tmp/swarm-token"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ------------------------------- LOGGING --------------------------------------
log()   { echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $*${NC}" | tee -a "$LOG_FILE"; }
warn()  { echo -e "${YELLOW}[WARN] $*${NC}" | tee -a "$LOG_FILE"; }
error() { echo -e "${RED}[ERROR] $*${NC}" | tee -a "$LOG_FILE" >&2; exit 1; }
info()  { echo -e "${BLUE}[INFO] $*${NC}" | tee -a "$LOG_FILE"; }

# ------------------------------- PREREQUISITES -------------------------------
install_prereqs() {
  log "Installing system prerequisites..."

  # Update package index
  apt update -y

  # Core tools
  apt install -y \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    software-properties-common \
    jq

  # Install yq (latest stable)
  if ! command -v yq &>/dev/null; then
    log "Installing yq..."
    YQ_VERSION="v4.44.3"
    YQ_BINARY="yq_linux_amd64"
    curl -L "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/${YQ_BINARY}" \
      -o /usr/local/bin/yq
    chmod +x /usr/local/bin/yq
  fi

  # Install Docker Compose v2 (CLI plugin)
  if ! docker compose version &>/dev/null; then
    log "Installing Docker Compose v2..."
    mkdir -p /usr/local/lib/docker/cli-plugins
    COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | jq -r .tag_name)
    curl -L "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-linux-x86_64" \
      -o /usr/local/lib/docker/cli-plugins/docker-compose
    chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
  fi

  log "Prerequisites installed."
}

# ------------------------------- HELPERS --------------------------------------
usage() {
  cat <<EOF
Usage: $0 --machine [node1|node2|devbox]

Examples:
  $0 --machine node1
  $0 --machine devbox

Logs: $LOG_FILE
EOF
  exit 1
}

require_root() {
  if [[ $EUID -ne 0 ]]; then
    error "This script must be run as root (use sudo)"
  fi
}

check_machine() {
  case "$1" in
    node1|node2|devbox) return 0 ;;
    *) error "Invalid machine: $1. Must be node1, node2, or devbox." ;;
  esac
}

validate_env() {
  local required_vars=(
    NODE1_IP NODE2_IP DEVBOX_IP
    NODE1_DOMAIN NODE2_DOMAIN DEVBOX_DOMAIN
    TAILSCALE_AUTHKEY LETSENCRYPT_EMAIL
    POSTGRES_PASSWORD HARBOR_ADMIN_PASSWORD
    GITEA_ADMIN_PASSWORD NEXTCLOUD_ADMIN_PASSWORD
  )
  for var in "${required_vars[@]}"; do
    if [[ -z "${!var:-}" ]]; then
      error "Required environment variable $var is not set"
    fi
  done
}

load_inventory() {
  # Load local secrets if present
  if [[ -f "${SCRIPT_DIR}/.env.inventory" ]]; then
    log "Loading secrets from .env.inventory"
    set -a  # auto-export
    source "${SCRIPT_DIR}/.env.inventory"
    set +a
  else
    warn ".env.inventory not found — ensure required env vars are set"
  fi
  validate_env

  if [[ ! -f "$INVENTORY" ]]; then
    warn "inventory.yml not found. Using defaults."
    return
  fi

  log "Loading inventory from $INVENTORY..."
  local yaml
  yaml=$(yq e ".[] | select(.machine == \"$MACHINE\")" "$INVENTORY")
  if [[ -z "$yaml" || "$yaml" == "null" ]]; then
    warn "No entry for machine '$MACHINE' in inventory.yml"
    return
  fi

  # Export all env vars
  while IFS="=" read -r key value; do
    [[ -z "$key" ]] && continue
    export "$key"="$value"
    info "  $key=$value"
  done < <(echo "$yaml" | yq e '.env // {} | to_entries | .[] | .key + "=" + .value' -)
}

# ------------------------------- MAIN ----------------------------------------
main() {
  local machine=""
  while [[ $# -gt 0 ]]; do
    case $1 in
      --machine)
        machine="$2"
        shift 2
        ;;
      -h|--help)
        usage
        ;;
      *)
        error "Unknown option: $1"
        ;;
    esac
  done

  [[ -z "$machine" ]] && usage
  export MACHINE="$machine"

  require_root
  check_machine "$MACHINE"

  # Ensure log directory
  mkdir -p "$(dirname "$LOG_FILE")"

  log "=== compute-infra setup starting for $MACHINE ==="

  # 1. Install prereqs
  install_prereqs

  # 2. Load inventory
  load_inventory

  # 3. Common setup
  log "Running common setup..."
  "${SCRIPT_DIR}/scripts/common/install-docker.sh"
  "${SCRIPT_DIR}/scripts/common/firewall.sh"

  # 4. Machine-specific setup
  case "$MACHINE" in
    node1)
      log "Configuring node1: Swarm manager + PoC stack"
      "${SCRIPT_DIR}/scripts/node1/swarm-init.sh"
      "${SCRIPT_DIR}/scripts/node1/deploy-poc.sh"
      ;;

    node2)
      log "Configuring node2: GPU worker"
      "${SCRIPT_DIR}/scripts/node2/gpu-setup.sh"

      if [[ -f "$SWARM_TOKEN_FILE" ]]; then
        local manager_ip
        manager_ip=$(grep -A1 "machine: node1" "$INVENTORY" | grep ip | awk '{print $2}' || echo "node1")
        log "Joining swarm at $manager_ip:2377"
        docker swarm join --token "$(cat "$SWARM_TOKEN_FILE")" "$manager_ip:2377"
      else
        warn "Swarm token not found. Run setup on node1 first."
      fi
      ;;

    devbox)
      log "Configuring devbox: Global workstation"
      "${SCRIPT_DIR}/scripts/devbox/tailscale.sh"

      local services=(traefik gitea nextcloud arch-vnc)
      for svc in "${services[@]}"; do
        local yml="${SCRIPT_DIR}/scripts/devbox/${svc}.yml"
        if [[ -f "$yml" ]]; then
          log "Deploying $svc..."
          docker compose -f "$yml" up -d
        else
          warn "$yml not found — skipping"
        fi
      done
      ;;
  esac

  log "=== $MACHINE setup complete! ==="
  log "Log: $LOG_FILE"
  log "Next: Run on other machines or use arch-dev CLI"
}

# ------------------------------- RUN -----------------------------------------
main "$@"