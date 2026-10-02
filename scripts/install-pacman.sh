#!/usr/bin/env bash
# install-pacman.sh -- Arch Linux / EndeavourOS / Manjaro (pacman).
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

PM=pacman

install() {
    info "package manager family: $PM"
    have_root "$@" || return 1
    require_cmd pacman || return 1

    # --needed: skip packages already installed; --noconfirm: non-interactive.
    pacman -S --needed --noconfirm \
        qemu-full libvirt virt-install virt-manager edk2-ovmf \
        cloud-utils genisoimage dnsmasq bridge-utils iproute2 \
        curl unzip openssh 2>/dev/null \
        || { fail "pacman install failed (check package names on your Arch-based distro)"; return 1; }

    if command -v systemctl >/dev/null 2>&1; then
        systemctl enable --now libvirtd >/dev/null 2>&1 \
            || systemctl enable --now libvirtd.service >/dev/null 2>&1 \
            || warn "could not enable libvirtd"
    fi
    return 0
}

install "$@"
exit "$EXIT_CODE"
