# Compute Infra

**Your secure, terminal-only, 3-machine cloud:**

- **`node1`**: Eink-net Manager (Docker Swarm, MQTT, PostgreSQL, Harbor)
- **`node2`**: Eink-net Worker + GPU (math_service, heavy apps)
- **`devbox`**: Global Dev Workstation (Gitea, Nextcloud, Omarchy VNC)

> **Opinionated, No web UI for the Eink-net. No VSCode. Neovim-first. Omarchy-first.**

---

## Features

| Feature | Status |
|-------|--------|
| **One-command setup** per machine | `setup.sh --machine node1` |
| **Omarchy VNC compute instances** | `arch-dev --ram 8G --storage 50G --host node3` |
| **Secure VNC + SSH** | TLS-wrapped VNC, SSH key-only |
| **Global access** | Tailscale + Traefik + Let’s Encrypt |
| **Git + Files** | Gitea + Nextcloud |
| **GPU passthrough** | `node2` ready |
| **Zero public PoC exposure** | Only `devbox` has 80/443 |

---

## Repository Structure

```
compute-infra/
│
├── README.md                     # Full setup guide
├── setup.sh                      # Master installer
├── inventory.yml                 # Machine roles
├── certs/                        # TLS certs (generated)
├── docker/                       # Docker images
│   └── omarchy-vnc/Dockerfile
├── scripts/
│   ├── node1/                    # PoC cluster
│   │   ├── swarm-init.sh
│   │   ├── deploy-poc.sh
│   │   └── docker-compose.yml
│   ├── node2/                    # GPU worker
│   │   └── gpu-setup.sh
│   ├── devbox/                   # Dev workstation
│   │   ├── tailscale.sh
│   │   ├── traefik.yml
│   │   ├── gitea.yml
│   │   ├── nextcloud.yml
│   │   └── arch-vnc.yml
│   └── common/
│       ├── install-docker.sh
│       ├── install-nvidia.sh
│       └── firewall.sh
├── cli/
│   ├── arch-dev                  # CLI binary
│   ├── arch-dev.py               # Source
│   └── certs/                    # Client certs
├── api/
│   ├── api.py                    # Flask API on node3
│   └── requirements.txt
├── minarchy/
│   ├── create-base-qcow2.sh      # Base Minarchy image
│   └── install.sh                # Auto-install script
└── .gitignore
```

---

## Prerequisites

| Machine | OS | Network |
|--------|----|--------|
| `node1` | Ubuntu 22.04 LTS | Public IP |
| `node2` | Ubuntu 22.04 LTS | Private |
| `devbox` | Ubuntu 22.04 LTS | Public IP |

> All machines must have **64 GB RAM** and **SSD**.

---

## Step 1: Clone & Bootstrap

```bash
git clone https://git.yourdomain.com/infra/3node.git
cd 3node
```

---

## Step 2: Install on Each Machine

### On `node1` (PoC Manager)

```bash
./setup.sh --machine node1
```

### On `node2` (GPU Worker)

```bash
./setup.sh --machine node2
```

### On `devbox` (Dev Workstation)

```bash
./setup.sh --machine devbox
```

---

## Step 3: Use the `arch-dev` CLI

### Install CLI (on your laptop)

```bash
# Copy from devbox
scp devbox:~/3node/cli/arch-dev ~/.local/bin/
scp -r devbox:~/3node/cli/certs ~/.arch-dev/

# Or install from repo
cp cli/arch-dev ~/.local/bin/
mkdir -p ~/.arch-dev && cp cli/certs/* ~/.arch-dev/
```

### Launch Omarchy Instance

```bash
arch-dev --ram 8G --storage 50G --host node3
```

**Output:**
```
VNC (TLS): 203.0.113.10:6201
SSH (key): 203.0.113.10:2215
Omarchy ready — connect and code
```

### Connect

```bash
# Run the helper
./scripts/devbox/vnc-tunnel.sh
# VNC (browser or client)
vncviewer 203.0.113.10:6201
# OR one-liner (anywhere):
vncviewer -via devbox.yourdomain.com:2222 localhost:5901

# SSH
ssh -p 2215 omarchy@203.0.113.10
```

> Your **Omarchy desktop** boots — **Neovim, git, build tools — all preinstalled**.

---

## Services on `devbox`

| Service | URL | Access |
|-------|-----|--------|
| **Gitea** | `https://git.yourdomain.com` | Git + browser |
| **Nextcloud** | `https://files.yourdomain.com` | WebDAV + client |
| **Omarchy VNC** | `https://omarchy-*.node3.yourdomain.com` | Browser |

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

**You now control a private, secure, Omarchy-powered cloud from your terminal.**

> **Next steps?**  
> - `arch-dev list` / `kill`  
> - Auto-shutdown after idle  
> - GPU passthrough (`--gpu`)  
> - `make deploy` with Ansible

Just ask — I’ll build it.
