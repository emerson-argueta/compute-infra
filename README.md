# Compute Infra

**Terminal-first, 3-machine private cloud**

- `node1` → Swarm manager (PostgreSQL, Harbor) – private only
- `node2` → GPU worker – private only
- `devbox` → public workstation (Traefik, Gitea, Nextcloud, Omarchy VMs)

**Only devbox exposes ports 80/443 to the internet.**

### Features

| Feature                       | Command                                  |
| ----------------------------- | ---------------------------------------- |
| One-command setup per machine | `sudo ./setup.sh devbox`                 |
| Omarchy KVM instances         | `arch-dev create --ram 8G --storage 50G` |
| Global access                 | Tailscale + Traefik + Let’s Encrypt      |
| Git + Files                   | Gitea + Nextcloud on devbox              |
| GPU-ready worker              | node2 has NVIDIA container toolkit       |

### Prerequisites

| Machine | OS               | Network                                              |
| ------- | ---------------- | ---------------------------------------------------- |
| node1   | Ubuntu 22.04 LTS | Private/firewalled (Swarm ports blocked)             |
| node2   | Ubuntu 22.04 LTS | Private only                                         |
| devbox  | Ubuntu 22.04 LTS | Public IP + DNS A record for `devbox.yourdomain.com` |

**Critical**: Swarm ports (2377, 7946, 4789) must **never** be public.

### DEVBOX SETUP (~30–45 min)

1. **Clone the repo**

   ```bash
   sudo apt update && sudo apt install -y git
   git clone https://git.yourdomain.com/infra/compute-infra.git
   cd compute-infra
   ```

2. **Create `.env.inventory` (never commit)**

   ```bash
   cp .env.inventory.example .env.inventory
   nano .env.inventory
   ```

   Replace every value in the example file (IPs, domains, secrets, your SSH pubkey for VMs).

3. **Run setup**

   ```bash
   sudo ./setup.sh devbox
   ```

4. **Verify**

   ```bash
   tailscale status                  # devbox should be online
   curl -k https://localhost/health  # should return {"status":"ok"}
   ```

Public services (HTTPS + Let’s Encrypt):

- Traefik dashboard: <https://traefik.devbox.yourdomain.com>
- Gitea: <https://git.devbox.yourdomain.com>
- Nextcloud: <https://files.devbox.yourdomain.com>

### Install `arch-dev` CLI on your laptop

```bash
scp vm-manager@devbox.yourdomain.com:/opt/compute-infra/cli/arch-dev ~/.local/bin/arch-dev
chmod +x ~/.local/bin/arch-dev
```

### Use the CLI

```bash
arch-dev --help
```

**Create a VM**

```bash
arch-dev create --ram 16G --storage 100G
```

Example output:

```
Creating omarchy-16g-100g-a1b2c3 (16G, 100G)...
Created: omarchy-16g-100g-a1b2c3
VNC: use SSH tunnel below

# Graphical desktop (VNC over SSH tunnel)
vncviewer -via vm-manager@devbox.yourdomain.com localhost:5907

Tip: Use 'ssh vm-manager@devbox.yourdomain.com virsh console omarchy-16g-100g-a1b2c3' for text console
```

**List VMs**

```bash
arch-dev list
```

**Destroy a VM**

```bash
arch-dev kill omarchy-16g-100g-a1b2c3
```

### Private nodes (node1 & node2)

```bash
# On node1 (run first)
sudo ./setup.sh node1

# On node2
sudo ./setup.sh node2
```

They join the Swarm over Tailscale automatically.

### Security notes

- Only devbox has public ports
- VNC is bound to localhost and tunneled over SSH (not native TLS)
- `.env.inventory` contains plaintext secrets – protect it
- Swarm is only reachable via Tailscale
- Always verify git tag signatures before running `setup.sh`

### Useful commands

```bash
tailscale status
sudo ufw status verbose
arch-dev list
```

### Troubleshooting

| Issue                   | Fix                                                           |
| ----------------------- | ------------------------------------------------------------- |
| Let’s Encrypt fails     | Check DNS, wait 5 min, `docker logs traefik`                  |
| VNC black screen        | Wait 60–90s after create for VM boot                          |
| VM creation hangs       | Check `ssh vm-manager@devbox.yourdomain.com virsh list --all` |
| node2 didn’t join Swarm | Re-run setup on node1 first                                   |

MIT © Emerson Argueta

