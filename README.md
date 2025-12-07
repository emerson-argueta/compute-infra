# Compute Infra
**Secure, terminal-first, 3-machine private cloud**

- **`node1`**: Docker Swarm manager (PostgreSQL, Harbor, MQTT) – **no public ports except Tailscale**
- **`node2`**: GPU worker node – private network only
- **`devbox`**: Global workstation – **only machine with public 80/443**

> **Opinionated stack. No web UIs for the cluster itself. Neovim-first. Omarchy-first. No VSCode.**

---
## Features
| Feature                        | Status          |
|-------------------------------|-----------------|
| One-command setup per machine | `sudo ./setup.sh --machine devbox` |
| Omarchy KVM instances         | `arch-dev create --ram 8G --storage 50G` |
| VNC + SSH over SSH tunnels    | No plaintext 5900 or 22 exposed |
| Global access                 | Tailscale + Traefik + Let’s Encrypt |
| Git + Files                   | Gitea + Nextcloud on devbox |
| GPU-ready worker              | node2 has NVIDIA container toolkit |

---
## Prerequisites
| Machine | OS                  | Network Requirements                              |
|---------|---------------------|---------------------------------------------------|
| node1   | Ubuntu 22.04 LTS    | Private or firewalled – **Swarm ports NOT public** |
| node2   | Ubuntu 22.04 LTS    | Private only                                      |
| devbox  | Ubuntu 22.04 LTS    | Public IP + DNS A record → `devbox.yourdomain.com` |

> **Critical**: Only `devbox` may expose ports 80/443 to the internet.  
> node1 and node2 must have Docker Swarm ports (2377, 7946, 4789) blocked from the public internet.

---
# DEVBOX SETUP GUIDE (Public-facing Workstation)

**Time**: ~30–45 minutes on first run  
**Requirements**: Fresh Ubuntu 22.04, public IP, 64 GB RAM + NVMe recommended

### STEP 1 – Clone the Repo
```bash
sudo apt update && sudo apt install -y git
git clone https://git.yourdomain.com/infra/compute-infra.git
cd compute-infra
```

### STEP 2 – Create `.env.inventory` (NEVER commit this file)
```bash
cp .env.inventory.example .env.inventory
nano .env.inventory
```

**.env.inventory.example** (copy this, then replace every value):
```env
# === IPs (private or public) ===
NODE1_IP=203.0.113.10
NODE2_IP=10.0.0.2
DEVBOX_IP=203.0.113.20

# === Domains ===
NODE1_DOMAIN=node1.yourdomain.com
NODE2_DOMAIN=node2.yourdomain.com
DEVBOX_DOMAIN=devbox.yourdomain.com

# === Secrets – CHANGE ALL OF THESE ===
TAILSCALE_AUTHKEY=tskey-auth-XXXXXXXXXXXXXXXXXXXXXXXX
LETSENCRYPT_EMAIL=you@yourdomain.com

POSTGRES_PASSWORD=generate-a-very-long-random-string-here
HARBOR_ADMIN_PASSWORD=another-very-long-random-string
GITEA_ADMIN_USER=admin
GITEA_ADMIN_PASSWORD=yet-another-long-random-string
NEXTCLOUD_ADMIN_USER=admin
NEXTCLOUD_ADMIN_PASSWORD=super-long-and-random
NEXTCLOUD_DB_ROOT_PASSWORD=even-longer-random
NEXTCLOUD_DB_PASSWORD=random-again

# Your personal SSH public key for Omarchy VMs
OMARCHY_SSH_PUBKEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... you@yourlaptop"
```

### STEP 3 – Run Setup
```bash
sudo ./setup.sh --machine devbox
```

This installs Docker, Tailscale, Traefik, Gitea, Nextcloud, and the Omarchy API.

### STEP 4 – Verify
```bash
curl -k https://localhost/health        # → {"status":"ok"}
tailscale status                        # should show devbox online
```

Public URLs (Let’s Encrypt certificates issued automatically):
- Traefik Dashboard : https://traefik.devbox.yourdomain.com
- Gitea             : https://git.devbox.yourdomain.com
- Nextcloud         : https://files.devbox.yourdomain.com

### STEP 5 – Install `arch-dev` CLI on Your Laptop
```bash
# From your laptop/workstation
scp devbox.yourdomain.com:/opt/compute-infra/cli/arch-dev ~/.local/bin/
scp devbox.yourdomain.com:/opt/compute-infra/cli/inventory.yml ~/.arch-dev/
chmod +x ~/.local/bin/arch-dev
```

### STEP 6 – Launch Your First VM
```bash
arch-dev create --ram 8G --storage 50G --host devbox
```

Example output:
```
Created: omarchy-8g-50g-x7f9
SSH port: 2217
VNC: use SSH tunnel below
```

### STEP 7 – Connect
```bash
# SSH (recommended)
ssh omarchy@devbox.yourdomain.com -p 2217

# Graphical desktop (VNC over SSH tunnel – NOT TLS-wrapped, just tunneled)
vncviewer -via omarchy@devbox.yourdomain.com:2217 localhost:5901
```

---
## Setting Up node1 and node2 (Private Machines)

```bash
# On node1 (run first)
sudo ./setup.sh --machine node1

# On node2 (after node1 is done)
sudo ./setup.sh --machine node2
```

They will automatically join the Swarm over Tailscale.  
**Never expose Swarm ports to the public internet.**

---
## Security Notes (No Sugar-Coating)
- Only `devbox` has public 80/443
- VNC is **tunneled over SSH**, not TLS-wrapped native VNC
- All passwords are in plain-text `.env.inventory` on disk – treat it like `/etc/shadow`
- Swarm control plane is only reachable over Tailscale → internet exposure = instant compromise
- Supply-chain risk: always verify git tag signatures before running `setup.sh` on a new machine

---
## Useful Commands
```bash
arch-dev list                  # running VMs
arch-dev kill <name>           # destroy VM
tailscale status               # private mesh network
sudo ufw status verbose        # only 80/443 + Tailscale should be open on devbox
```

---
## Troubleshooting
| Symptom                        | Fix |
|--------------------------------|-----|
| Let’s Encrypt fails            | Check DNS, wait 5 min, check `docker logs traefik` |
| arch-dev: connection refused   | Wait 30s after `create`, or check API container logs |
| VNC black screen               | Wait 60–90s for VM boot |
| node2 didn’t join Swarm        | Re-run setup on node1 first, or manually run `docker swarm join-token worker` |

---
## Contributing
1. Fork
2. Branch: `feat/whatever` or `fix/whatever`
3. Commit + PR

## License
MIT © Emerson Argueta