#!/usr/bin/env bash
set -euo pipefail

# Config (consider moving to ~/.ssh/config for cleanliness)
HOST="devbox.yourdomain.com"
USER="vm-manager"
BASE_IMAGE="/opt/compute-infra/omarchy/base.qcow2"

usage() {
  cat <<EOF
Usage:
  arch-dev create [--ram 8G] [--storage 50G]
  arch-dev list
  arch-dev kill <name>
  arch-dev (-h | --help)

Options:
  -h, --help    Show this help message and exit
EOF
  exit 0
}

# Show help if requested or no args
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" || $# -eq 0 ]]; then
  usage
fi

CMD="$1"; shift

RAM="8G"
STORAGE="50G"

case "$CMD" in
  create)
    while [[ $# -gt 0 ]]; do
      case $1 in
        --ram) RAM="$2"; shift 2 ;;
        --storage) STORAGE="$2"; shift 2 ;;
        *) echo "Unknown option: $1"; usage ;;
      esac
    done

    [[ $RAM =~ ^[0-9]+G$ ]] || { echo "Invalid RAM: $RAM"; exit 1; }
    [[ $STORAGE =~ ^[0-9]+G$ ]] || { echo "Invalid storage: $STORAGE"; exit 1; }

    RAM_MIB=$(( ${RAM%G} * 1024 ))
    ID=$(od -An -N3 -tx1 /dev/urandom | tr -d ' \n')
    NAME="omarchy-${RAM,,}-${STORAGE,,}-${ID}"

    echo "Creating $NAME ($RAM, $STORAGE)..."

    ssh -o StrictHostKeyChecking=no "$USER@$HOST" bash <<EOF
set -e
qemu-img create -f qcow2 -b $BASE_IMAGE -F qcow2 /var/lib/libvirt/images/$NAME.qcow2 $STORAGE
virt-install --import --name $NAME \
  --memory $RAM_MIB --vcpus 4 --disk /var/lib/libvirt/images/$NAME.qcow2 \
  --graphics vnc,listen=127.0.0.1 --network bridge=virbr0 \
  --os-variant archlinux --noautoconsole --wait 60 || {
    virsh destroy $NAME 2>/dev/null || true
    virsh undefine $NAME 2>/dev/null || true
    rm -f /var/lib/libvirt/images/$NAME.qcow2
    echo "VM creation failed"
    exit 1
  }
EOF

    for i in {1..10}; do
      VNC_DISPLAY=$(ssh -o StrictHostKeyChecking=no "$USER@$HOST" "virsh vncdisplay $NAME 2>/dev/null | tail -1" || true)
      [[ -n "$VNC_DISPLAY" && "$VNC_DISPLAY" != ":"* ]] && break
      sleep 2
    done

    VNC_PORT=$((5900 + ${VNC_DISPLAY#:}))

    echo "Created: $NAME"
    echo "VNC: use SSH tunnel below"
    echo
    echo "# Graphical desktop (VNC over SSH tunnel)"
    echo "vncviewer -via $USER@$HOST localhost:$VNC_PORT"
    echo
    echo "Tip: Use 'ssh $USER@$HOST virsh console $NAME' for text console"
    ;;

  list)
    ssh -o StrictHostKeyChecking=no "$USER@$HOST" "virsh list --all"
    ;;

  kill)
    [[ -z "${1:-}" ]] && { echo "Missing VM name"; usage; }
    NAME="$1"
    ssh -o StrictHostKeyChecking=no "$USER@$HOST" \
      "virsh destroy $NAME || true; virsh undefine $NAME || true; rm -f /var/lib/libvirt/images/$NAME.qcow2"
    echo "$NAME terminated"
    ;;

  *) echo "Unknown command: $CMD"; usage ;;
esac
