#!/bin/bash
# scripts/node2/gpu-setup.sh
# Full GPU worker setup for node2
# Run after base OS install

set -euo pipefail

log() { echo "[+] $*"; }
warn() { echo "[!] $*"; }
error() { echo "[ERROR] $*"; exit 1; }

log "Starting GPU worker setup for node2..."

# === 1. Install NVIDIA stack ===
log "Installing NVIDIA drivers, CUDA, and Container Toolkit..."
if [[ -f "../common/install-nvidia.sh" ]]; then
    source ../common/install-nvidia.sh
else
    error "install-nvidia.sh not found in ../common/"
fi

# === 2. Verify GPU ===
log "Verifying GPU access..."
if ! nvidia-smi &> /dev/null; then
    error "GPU not detected. Check hardware and drivers."
fi
log "GPU ready:"
nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv

# === 3. Join Docker Swarm ===
log "Joining Docker Swarm as worker..."
if ! docker info | grep -q "Swarm: active"; then
    # Get join token from node1
    if [[ -f "/tmp/swarm-join-token" ]]; then
        JOIN_TOKEN=$(cat /tmp/swarm-join-token)
    else
        warn "Swarm join token not found. Fetching from node1..."
        JOIN_TOKEN=$(ssh node1 "docker swarm join-token -q worker")
        echo "$JOIN_TOKEN" > /tmp/swarm-join-token
    fi

    MANAGER_IP=$(ssh node1 "hostname -I | awk '{print \$1}'")
    log "Joining swarm at $MANAGER_IP..."
    docker swarm join --token "$JOIN_TOKEN" "$MANAGER_IP:2377"
else
    log "Already part of swarm."
fi

# === 4. Label node for GPU scheduling ===
log "Labeling node for GPU workloads..."
docker node update $(hostname) --label-add gpu=true
docker node update $(hostname) --label-add type=worker-gpu

# === 5. Configure Docker for GPU (redundant but safe) ===
log "Ensuring Docker GPU runtime..."
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker

# === 6. Test GPU in container ===
log "Testing GPU passthrough..."
if ! docker run --rm --gpus all nvidia/cuda:12.2.0-base-ubuntu22.04 nvidia-smi; then
    error "GPU not visible in container."
fi

# === 7. Enable persistence mode ===
log "Enabling NVIDIA persistence mode..."
sudo nvidia-smi -pm 1 || warn "Persistence mode not supported (non-issue)"

# === 8. Optional: KVM GPU passthrough prep ===
log "Preparing for KVM GPU passthrough (if needed)..."
if ! grep -q "iommu=pt" /etc/default/grub; then
    sudo sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="/GRUB_CMDLINE_LINUX_DEFAULT="intel_iommu=on iommu=pt pcie_acs_override=downstream,multifunction /' /etc/default/grub
    sudo update-grub
    warn "IOMMU enabled. Reboot required for KVM passthrough."
fi

# === 9. Final status ===
log "node2 GPU worker setup complete!"
log "Node labels:"
docker node inspect $(hostname) --format '{{ range $k, $v := .Spec.Labels }}{{ $k }}={{ $v }}{{ println }}{{ end }}'

log "Reboot recommended for full IOMMU support (if using KVM passthrough)."
