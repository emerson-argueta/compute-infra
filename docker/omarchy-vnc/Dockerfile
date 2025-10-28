FROM archlinux:latest
RUN pacman -Syu --noconfirm && \
    pacman -S --noconfirm xorg openbox x11vnc novnc \
                          neovim git curl wget htop \
                          omarchy-packages
CMD ["/usr/bin/supervisord"]
