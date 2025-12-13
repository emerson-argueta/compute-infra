#!/usr/bin/env bash
# roles/common/docker.sh
set -euo pipefail

log() { echo "[docker] $*"; }

# Docker Engine + Compose plugin
if ! command -v docker >/dev/null; then
  log "Installing Docker Engine from official repo"
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    | gpg --dearmor -o /etc/apt/keyrings/docker.gpg --yes
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
    https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
    | tee /etc/apt/sources.list.d/docker.list > /dev/null

  apt-get update -y
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
else
  log "Docker Engine already installed"
fi

# NVIDIA Container Toolkit + minimal driver (node2 only)
if [[ "${ROLE:-}" == "node2" ]]; then
  if ! nvidia-smi &>/dev/null; then
    log "Installing latest open-kernel NVIDIA driver"
    ubuntu-drivers install --gpgpu
  fi

  if ! command -v nvidia-ctk &>/dev/null; then
    log "Installing nvidia-container-toolkit"
    distribution=$(. /etc/os-release && echo "$ID$VERSION_ID")
    curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
      | gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg --yes

    curl -s -L https://nvidia.github.io/libnvidia-container/$distribution/libnvidia-container.list \
      | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
      | tee /etc/apt/sources.list.d/nvidia-container-toolkit.list > /dev/null

    apt-get update -y
    apt-get install -y nvidia-container-toolkit
  fi

  log "Configuring Docker NVIDIA runtime"
  nvidia-ctk runtime configure --runtime=docker
  systemctl restart docker
fi

log "Docker setup complete"
