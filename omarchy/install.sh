#!/bin/bash
# omarchy/install.sh
# Unattended installer for Omarchy (your Arch fork) in KVM VM
# Run on first boot from ISO → creates clean base image

set -euo pipefail

log() { echo "[+] $*"; }
error() { echo "[ERROR] $*"; exit 1; }

log "Starting Omarchy unattended install..."

# === 1. Wait for network ===
log "Waiting for network..."
until ping -c1 archlinux.org &>/dev/null; do sleep 2; done

# === 2. Partition disk ===
log "Partitioning /dev/vda..."
parted -s /dev/vda mklabel gpt
parted -s /dev/vda mkpart primary 1MiB 100%
mkfs.ext4 -F /dev/vda1
mount /dev/vda1 /mnt

# === 3. Install base system ===
log "Installing base system..."
pacstrap /mnt base linux linux-firmware

# === 4. Generate fstab ===
genfstab -U /mnt >> /mnt/etc/fstab

# === 5. Chroot and configure ===
log "Configuring system in chroot..."
arch-chroot /mnt /bin/bash <<'EOF'
set -euo pipefail

# Locale
echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# Hostname
echo "omarchy-vm" > /etc/hostname
cat > /etc/hosts <<HOSTS
127.0.0.1   localhost
::1         localhost
127.0.1.1   omarchy-vm.localdomain omarchy-vm
HOSTS

# Timezone
ln -sf /usr/share/zoneinfo/UTC /etc/localtime
hwclock --systohc

# Root password (random, will be locked)
openssl rand -base64 32 | passwd --stdin root

# === Create omarchy user ===
useradd -m -G wheel -s /bin/bash omarchy
echo "omarchy:$(openssl rand -base64 32)" | chpasswd
echo "omarchy ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/omarchy

# === SSH ===
pacman -Syu --noconfirm openssh
systemctl enable sshd
mkdir -p /home/omarchy/.ssh
chmod 700 /home/omarchy/.ssh
chown omarchy:omarchy /home/omarchy/.ssh

# === VNC + Desktop ===
pacman -Syu --noconfirm \
    xorg-server xorg-xinit openbox \
    x11vnc websockify \
    neovim git curl wget htop tree fzf ripgrep fd bat \
    lightdm lightdm-gtk-greeter

# Enable LightDM
systemctl enable lightdm

# x11vnc service
cat > /etc/systemd/system/x11vnc.service <<VNC
[Unit]
Description=x11vnc server
After=lightdm.service

[Service]
Type=simple
ExecStart=/usr/bin/x11vnc -localhost -nopw -forever -rfbport 5901
Restart=always
User=omarchy

[Install]
WantedBy=multi-user.target
VNC
systemctl enable x11vnc.service

# noVNC (websockify)
cat > /etc/systemd/system/novnc.service <<NOVNC
[Unit]
Description=noVNC proxy
After=x11vnc.service

[Service]
Type=simple
ExecStart=/usr/bin/websockify --web=/usr/share/websockify 6080 localhost:5901
Restart=always
User=omarchy

[Install]
WantedBy=multi-user.target
NOVNC
systemctl enable novnc.service

# === Your Omarchy packages ===
# Replace with your actual package list or PKGBUILDs
pacman -Syu --noconfirm \
    omarchy-core omarchy-dev omarchy-tools \
    || echo "Custom packages not in repo — skipping"

# === Final cleanup ===
rm -f /etc/systemd/system/getty@.service
systemctl set-default graphical.target

EOF

# === 6. Unmount and finish ===
log "Installation complete. Unmounting..."
umount -R /mnt

log "Omarchy base image ready. Shutting down in 5s..."
sleep 5
poweroff
