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
  apt update -y
  apt install -y \
    ca-certificates curl gnupg lsb-release software-properties-common jq \
    qemu-kvm libvirt-clients libvirt-daemon-system virtinst \
    bridge-utils stunnel4 libguestfs-tools
  # yq
  if ! command -v yq &>/dev/null; then
    log "Installing yq..."
    local YQ_VERSION="v4.44.3" YQ_BINARY="yq_linux_amd64"
    curl -L "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/${YQ_BINARY}" \
      -o /usr/local/bin/yq
    chmod +x /usr/local/bin/yq
  fi

  # Docker Compose v2 plugin
  if ! docker compose version &>/dev/null; then
    log "Installing Docker Compose v2..."
    mkdir -p /usr/local/lib/docker/cli-plugins
    local COMPOSE_VERSION
    COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | jq -r .tag_name)
    curl -L "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-linux-x86_64" \
      -o /usr/local/lib/docker/cli-plugins/docker-compose
    chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
  fi

  systemctl enable --now libvirtd

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
  (( EUID == 0 )) || error "This script must be run as root (use sudo)"
}

check_machine() {
  case "$1" in node1|node2|devbox) return 0 ;; *) error "Invalid machine: $1" ;; esac
}

# -------------------------------------------------------------------------
# 1. Load .env.inventory (git-ignored) – secrets & IPs
# 2. Validate that every required var is present
# -------------------------------------------------------------------------
load_secrets_and_validate() {
  local env_file="${SCRIPT_DIR}/.env.inventory"

  if [[ -f "$env_file" ]]; then
    log "Loading secrets from $env_file"
    set -a
    # shellcheck source=/dev/null
    source "$env_file" || error "Failed to source $env_file"
    set +a
  else
    warn "$env_file not found – relying on exported environment variables"
  fi

  # ---- required variables ------------------------------------------------
  local -a required_vars=(
    NODE1_IP NODE2_IP DEVBOX_IP
    NODE1_DOMAIN NODE2_DOMAIN DEVBOX_DOMAIN
    TAILSCALE_AUTHKEY LETSENCRYPT_EMAIL
    POSTGRES_PASSWORD HARBOR_ADMIN_PASSWORD
    GITEA_ADMIN_USER GITEA_ADMIN_PASSWORD
    NEXTCLOUD_ADMIN_USER NEXTCLOUD_ADMIN_PASSWORD
    NEXTCLOUD_DB_ROOT_PASSWORD NEXTCLOUD_DB_PASSWORD
    OMARCHY_SSH_PUBKEY
  )

  local -a missing=()
  for var in "${required_vars[@]}"; do
    [[ -z "${!var:-}" ]] && missing+=("$var")
  done

  (( ${#missing[@]} == 0 )) || {
    error "Missing required environment variables:\n  ${missing[*]}\n" \
          "Set them in .env.inventory or export them before running."
  }

  log "All required environment variables are present."
}

# -------------------------------------------------------------------------
# Load machine-specific block from inventory.yml and export its .env map
# -------------------------------------------------------------------------
load_inventory() {
  load_secrets_and_validate   # <-- secrets first

  [[ -f "$INVENTORY" ]] || { warn "inventory.yml not found – using defaults."; return; }

  log "Loading inventory from $INVENTORY..."
  local yaml
  yaml=$(yq e ".[] | select(.machine == \"$MACHINE\")" "$INVENTORY")
  [[ -z "$yaml" || "$yaml" == "null" ]] && { warn "No entry for '$MACHINE' in inventory.yml"; return; }

  # Export top-level fields (ip, domain, …) – optional
  local ip domain
  ip=$(echo "$yaml" | yq e '.ip // empty' -)
  domain=$(echo "$yaml" | yq e '.domain // empty' -)
  [[ -n "$ip" ]]     && export NODE_IP="$ip"
  [[ -n "$domain" ]] && export NODE_DOMAIN="$domain"

  # Export .env sub-map
  while IFS="=" read -r key value; do
    [[ -z "$key" ]] && continue
    export "$key"="$value"
    info " $key=$value"
  done < <(echo "$yaml" | yq e '.env // {} | to_entries | .[] | .key + "=" + .value' -)
  # === Export FQDNs from inventory.yml (devbox only) ===
  if [[ "$MACHINE" == "devbox" ]]; then
    local DEVBOX_YAML
    DEVBOX_YAML=$(yq e '.[] | select(.machine == "devbox")' "$INVENTORY")
    [[ -n "$DEVBOX_YAML" ]] || error "devbox not found in inventory.yml"
    export DEVBOX_DOMAIN=$(echo "$DEVBOX_YAML" | yq e '.domain' -)
    export API_FQDN=$(echo "$DEVBOX_YAML" | yq e '.subdomains.api + "." + .domain' -)
    export TRAEFIK_FQDN=$(echo "$DEVBOX_YAML" | yq e '.subdomains.traefik + "." + .domain' -)
    export GITEA_FQDN=$(echo "$DEVBOX_YAML" | yq e '.subdomains.gitea + "." + .domain' -)
    export NEXTCLOUD_FQDN=$(echo "$DEVBOX_YAML" | yq e '.subdomains.nextcloud + "." + .domain' -)
    log "FQDNs:"
    log "  API:        https://$API_FQDN"
    log "  Traefik:    https://$TRAEFIK_FQDN"
    log "  Gitea:      https://$GITEA_FQDN"
    log "  Nextcloud:  https://$NEXTCLOUD_FQDN"
  fi
}

# -------------------------------------------------------------------------
# Helper: safely read a field from inventory.yml (used for Swarm join)
# -------------------------------------------------------------------------
inventory_get() {
  local selector="$1"
  yq e "$selector" "$INVENTORY" 2>/dev/null || echo ""
}

# ------------------------------- MAIN ----------------------------------------
main() {
  local machine=""
  while (( $# )); do
    case $1 in
      --machine) machine="$2"; shift 2 ;;
      -h|--help) usage ;;
      *) error "Unknown option: $1" ;;
    esac
  done
  [[ -z "$machine" ]] && usage
  export MACHINE="$machine"

  require_root
  check_machine "$MACHINE"

  mkdir -p "$(dirname "$LOG_FILE")"
  log "=== compute-infra setup starting for $MACHINE ==="

  # 1. Install prereqs
  install_prereqs

  # 2. Load inventory + secrets + validation
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
        # Safer way to fetch node1's IP from inventory.yml
        local manager_ip
        manager_ip=$(inventory_get '.[] | select(.machine == "node1") | .ip')
        [[ -z "$manager_ip" ]] && manager_ip="node1"
        log "Joining swarm at $manager_ip:2377"
        docker swarm join --token "$(cat "$SWARM_TOKEN_FILE")" "$manager_ip:2377"
      else
        warn "Swarm token not found. Run setup on node1 first."
      fi
      ;;
    devbox)
      log "Configuring devbox: Global workstation"
      "${SCRIPT_DIR}/scripts/devbox/tailscale.sh"

      # === Deploy Docker services ===
      local services=(traefik gitea nextcloud api)
      for svc in "${services[@]}"; do
          local yml="${SCRIPT_DIR}/scripts/devbox/${svc}.yml"
          if [[ -f "$yml" ]]; then
              log "Deploying $svc..."
              docker compose -f "$yml" up -d
          else
              warn "$yml not found — skipping"
          fi
      done

      # === Final CLI Setup ===
      log "Preparing arch-dev CLI for users..."
      sudo mkdir -p /opt/compute-infra/cli
      sudo cp "${SCRIPT_DIR}/inventory.yml" /opt/compute-infra/cli/inventory.yml
      sudo cp "${SCRIPT_DIR}/cli/arch-dev" /opt/compute-infra/cli/arch-dev
      sudo chmod +x /opt/compute-infra/cli/arch-dev
      log "CLI ready. Users should run:"
      log " scp $DEVBOX_IP:/opt/compute-infra/cli/inventory.yml ~/.arch-dev/"
      log " scp $DEVBOX_IP:/opt/compute-infra/cli/arch-dev ~/.local/bin/"
      log " chmod +x ~/.local/bin/arch-dev"
      log "Then: arch-dev create --ram 8G --storage 50G --host devbox"
    ;;
  esac
 log "=== $MACHINE setup complete! ==="
 log "Log: $LOG_FILE"
 log "Next: Run on other machines or use 'arch-dev' CLI from your laptop"
}

# ------------------------------- RUN -----------------------------------------
main "$@"