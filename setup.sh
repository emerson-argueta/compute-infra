
---

### `setup.sh` (Master Installer)

```bash
#!/bin/bash
set -e

MACHINE=$1
if [[ -z "$MACHINE" ]]; then
  echo "Usage: $0 --machine [node1|node2|devbox]"
  exit 1
fi

echo "Setting up $MACHINE..."

# Common
./scripts/common/install-docker.sh
./scripts/common/firewall.sh

case $MACHINE in
  node1)
    ./scripts/node1/swarm-init.sh
    ./scripts/node1/deploy-poc.sh
    ;;
  node2)
    ./scripts/node2/gpu-setup.sh
    docker swarm join --token $(cat /tmp/swarm-token) $(hostname -I | awk '{print $1}'):2377
    ;;
  devbox)
    ./scripts/devbox/tailscale.sh
    docker-compose -f scripts/devbox/traefik.yml up -d
    docker-compose -f scripts/devbox/gitea.yml up -d
    docker-compose -f scripts/devbox/nextcloud.yml up -d
    docker-compose -f scripts/devbox/arch-vnc.yml up -d
    ;;
esac

echo "$MACHINE ready"
