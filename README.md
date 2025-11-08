# Compute Infra

**Your secure, terminal-only, 3-machine cloud:**

- **`node1`**: Eink-net Manager (Docker Swarm, MQTT, PostgreSQL, Harbor)
- **`node2`**: Eink-net Worker + GPU (math_service, heavy apps)
- **`devbox`**: Global Dev Workstation (Gitea, Nextcloud, Omarchy compute instace API)

> **Opinionated, No web UI for the Eink-net. No VSCode. Neovim-first. Omarchy-first.**

---

## Features

| Feature | Status |
|-------|--------|
| **One-command setup** per machine | `setup.sh --machine node1` |
| **Omarchy VNC compute instances** | `arch-dev --ram 8G --storage 50G --host devbox` |
| **Secure VNC + SSH** | TLS-wrapped VNC, SSH key-only |
| **Global access** | Tailscale + Traefik + Let’s Encrypt |
| **Git + Files** | Gitea + Nextcloud |
| **GPU passthrough** | `node2` ready |
| **Zero public PoC exposure** | Only `devbox` has 80/443 |

---

## Prerequisites

| Machine | OS | Network |
|--------|----|--------|
| `node1` | Ubuntu 22.04 LTS | Public IP |
| `node2` | Ubuntu 22.04 LTS | Private |
| `devbox` | Ubuntu 22.04 LTS | Public IP |

---

# **DEVBOX SETUP GUIDE**  
**Ubuntu 22.04 LTS → Fully Secure, Terminal-Only Cloud Workstation**

> **Time: 15 minutes**  
> **Requirements:**  
> - Ubuntu 22.04 LTS (fresh install)  
> - Public IP + DNS A record → `devbox.yourdomain.com`  
> - 64 GB RAM + SSD  
> - Internet access

---

## **STEP 1: Clone the Repo**

```bash
sudo apt update && sudo apt install -y git
git clone https://git.yourdomain.com/infra/compute-infra.git
cd compute-infra
```

---

## **STEP 2: Create `.env.inventory` (Secrets)**

```bash
nano .env.inventory
```

**Paste this — replace with your real values:**

```env
# === IPs ===
NODE1_IP=203.0.113.10
NODE2_IP=10.0.0.2
DEVBOX_IP=203.0.113.20

# === Domains ===
NODE1_DOMAIN=node1.yourdomain.com
NODE2_DOMAIN=node2.yourdomain.com
DEVBOX_DOMAIN=devbox.yourdomain.com

# === Secrets ===
TAILSCALE_AUTHKEY=tskey-auth-abc123def456ghi789
LETSENCRYPT_EMAIL=you@yourdomain.com

POSTGRES_PASSWORD=supersecret123
HARBOR_ADMIN_PASSWORD=admin123

GITEA_ADMIN_USER=admin
GITEA_ADMIN_PASSWORD=giteapass123

NEXTCLOUD_ADMIN_USER=admin
NEXTCLOUD_ADMIN_PASSWORD=nextcloudpass123
NEXTCLOUD_DB_ROOT_PASSWORD=rootpass123
NEXTCLOUD_DB_PASSWORD=dbpass123

# Your SSH public key (for Omarchy VMs)
OMARCHY_SSH_PUBKEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... you@yourlaptop"
```

> **Save: `Ctrl+O` → Enter → `Ctrl+X`**

---

## **STEP 3: Run Setup (One Command)**

```bash
sudo ./setup.sh --machine devbox
```

**What it does:**
1. Installs Docker, KVM, Tailscale, Traefik
2. Sets up UFW firewall (only 80/443 + Tailscale)
3. Deploys:
   - `traefik` (HTTPS reverse proxy)
   - `gitea` (Git)
   - `nextcloud` (Files)
   - `arch-dev-api` (VM manager)
4. Copies `arch-dev` CLI to `/opt/compute-infra/cli/`

---

## **STEP 4: Verify Services**

Wait 60 seconds, then:

```bash
curl -k https://localhost/health
# → {"status":"ok"}
```

Check URLs (from anywhere):

| Service | URL |
|-------|-----|
| Traefik Dashboard | `https://traefik.devbox.yourdomain.com` |
| Gitea | `https://git.devbox.yourdomain.com` |
| Nextcloud | `https://files.devbox.yourdomain.com` |

> **All use Let’s Encrypt TLS automatically.**

---

## **STEP 5: Install `arch-dev` CLI on Your Laptop**

```bash
# From your laptop
scp devbox.yourdomain.com:/opt/compute-infra/cli/arch-dev ~/.local/bin/
scp devbox.yourdomain.com:/opt/compute-infra/cli/inventory.yml ~/.arch-dev/
chmod +x ~/.local/bin/arch-dev
```

---

## **STEP 6: Launch Your First Omarchy VM**

```bash
arch-dev create --ram 8G --storage 50G --host devbox
```

**Example Output:**
```
Created: omarchy-8g-50g-x7f9
SSH: ssh omarchy@devbox.yourdomain.com -p 2217
VNC: vncviewer -via devbox.yourdomain.com:2217 localhost:5901
Omarchy ready — connect and code
```

---

## **STEP 7: Connect**

```bash
# SSH
ssh omarchy@devbox.yourdomain.com -p 2217

# VNC (graphical desktop)
vncviewer -via devbox.yourdomain.com:2217 localhost:5901
```

> **You now have a full Arch Linux desktop with Neovim, git, build tools.**

---

## **Done! Your Devbox Is Live**

| Command | Use |
|-------|-----|
| `arch-dev list` | Show running VMs |
| `arch-dev kill omarchy-8g-50g-x7f9` | Destroy VM |
| `tailscale status` | Check private network |
| `sudo ufw status verbose` | Verify firewall |

---

## **Next: Set Up `node1` and `node2`**

```bash
# On node1
sudo ./setup.sh --machine node1

# On node2
sudo ./setup.sh --machine node2
```

> They’ll auto-join Swarm and connect via Tailscale.

---

## Services on `devbox`

| Service | URL | Access |
|-------|-----|--------|
| **Gitea** | `https://git.yourdomain.com` | Git + browser |
| **Nextcloud** | `https://files.yourdomain.com` | WebDAV + client |
---

## Security

- **TLS everywhere**: Docker, libvirt, VNC, Traefik
- **SSH key-only**: No passwords
- **Per-client firewall**: UFW rules auto-added
- **Ephemeral ports**: Random VNC/SSH ports
- **Tailscale**: Private access to `node1`, `node2`

---

## Cleanup

```bash
# List running instances
docker ps | grep omarchy

# Kill
docker rm -f omarchy-8g-50g-abcd1234
```

---

## Troubleshooting

| Issue | Fix |
|------|-----|
| `arch-dev: connection refused` | Check `~/.arch-dev/node3.crt` |
| VNC black screen | Wait 60s after boot |
| SSH permission denied | Re-upload your public key |
| GPU not detected | Run `nvidia-smi` on `node2` |

---

## Contributing

1. Fork this repo
2. Create branch: `feat/gpu-passthrough`
3. Commit: `git commit -m "Add GPU passthrough"`
4. Push & PR

---

## License

MIT © Emerson Argueta

---