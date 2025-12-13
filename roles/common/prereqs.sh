#!/usr/bin/env bash
# roles/common/prereqs.sh
set -euo pipefail
log() { echo "[prereqs] $*"; }

log "Updating apt cache"
apt update -y

log "Installing base packages"
apt install -y \
  ca-certificates curl gnupg lsb-release jq \
  qemu-kvm libvirt-clients libvirt-daemon-system virtinst \
  bridge-utils libguestfs-tools

# yq – only if missing or wrong version
if ! command -v yq >/dev/null || ! yq --version | grep -q "v4\."; then
  log "Installing yq v4"
  curl -L https://github.com/mikefarah/yq/releases/download/v4.44.3/yq_linux_amd64 \
    -o /usr/local/bin/yq
  chmod +x /usr/local/bin/yq
fi

systemctl enable --now libvirtd >/dev/null

log "Prerequisites done"
