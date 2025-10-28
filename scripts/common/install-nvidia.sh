#!/bin/bash
# scripts/common/install-nvidia.sh
# Install NVIDIA drivers, CUDA, and Container Toolkit on Ubuntu 22.04
# Run on node2 (GPU worker)

set -euo pipefail

log() { echo "[+] $*"; }
warn() { echo "[!] $*"; }
error() { echo "[ERROR] $*"; exit 1; }

log "Starting NVIDIA + CUDA + Container Toolkit installation..."

# === 1. Update system ===
log "Updating package index..."
sudo apt update

# === 2. Install kernel headers and build tools ===
log "Installing build essentials..."
sudo apt install -y build-essential linux-headers-$(uname -r)

# === 3. Detect GPU ===
log "Detecting NVIDIA GPU..."
if ! command -v nvidia-smi &> /dev/null; then
    warn "nvidia-smi not found. Installing drivers..."
else
    log "GPU detected:"
    nvidia-smi --query-gpu=name,driver_version --format=csv,noheader
fi

# === 4. Install NVIDIA drivers (auto-detect) ===
log "Installing NVIDIA drivers..."
sudo ubuntu-drivers autoinstall || \
sudo apt install -y nvidia-driver-535 nvidia-utils-535

# Wait for driver to load
log "Waiting for driver to initialize..."
sleep 10
if ! nvidia-smi &> /dev/null; then
    error "NVIDIA driver failed to load. Check logs: dmesg | grep -i nvidia"
fi
log "Driver installed and active:"
nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv

# === 5. Install CUDA Toolkit ===
log "Installing CUDA Toolkit..."
sudo apt install -y cuda-toolkit-12-2 || \
sudo apt install -y cuda

# Add to PATH (persistent)
CUDA_BIN="/usr/local/cuda-12.2/bin"
if ! grep -q "$CUDA_BIN" /etc/environment; then
    sudo sed -i "s|PATH=\"|PATH=\"$CUDA_BIN:|g" /etc/environment
fi

# === 6. Install NVIDIA Container Toolkit ===
log "Installing NVIDIA Container Toolkit..."

# Add repo
distribution=$(. /etc/os-release && echo "$ID$VERSION_ID")
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
curl -s -L https://nvidia.github.io/libnvidia-container/$distribution/libnvidia-container.list | \
    sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
    sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

sudo apt update
sudo apt install -y nvidia-container-toolkit

# Configure Docker
log "Configuring Docker for GPU..."
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker

# === 7. Verify GPU in container ===
log "Testing GPU passthrough in container..."
if ! docker run --rm --gpus all nvidia/cuda:12.2.0-base-ubuntu22.04 nvidia-smi; then
    error "GPU not visible in container. Check nvidia-container-toolkit."
fi

log "NVIDIA + CUDA + Container Toolkit installed successfully!"
log "GPU ready for Docker and KVM passthrough."

# === 8. Optional: Enable persistence mode ===
log "Enabling NVIDIA persistence mode..."
sudo nvidia-smi -pm 1 || warn "Persistence mode not supported"

log "All done. Reboot recommended."
